# Worker Control CLI

> **Note:** This doc is now mirrored on the published site at
> `.site/docs/worker-control.md`; keep both versions aligned.

Stem ships a broker-backed control plane that lets operators inspect and revoke
work without restarts. The CLI subcommands live under `stem worker` and use the
same connection configuration as the rest of the toolchain.

## Commands

| Command | Purpose |
| ------- | ------- |
| `stem worker ping` | Broadcasts a control ping and prints worker responses. |
| `stem worker inspect` | Shows in-flight tasks (optionally revoked cache) per worker. |
| `stem worker stats` | Returns aggregate counters such as inflight count and queue depth. |
| `stem worker revoke` | Persists a revoke record and publishes the control message. |

Use `--namespace` to target non-default control namespaces; omit
`--worker` to broadcast to every worker.

## Persistent Revokes

Revocations are durable so new workers or restarts continue honouring them. The
CLI resolves the store in the following order:

1. `STEM_REVOKE_STORE_URL`
2. `STEM_RESULT_BACKEND_URL`
3. `STEM_BROKER_URL`

Supported backends are Redis (`redis://` / `rediss://`), Postgres
(`postgres://` / `postgresql://`), a newline-delimited file (`file://` or bare
path), and an in-memory store (for tests) via `memory://`.

Workers materialise the revoke set during startup, prune expired entries, and
refresh as new control messages arrive. The CLI writes through the store before
publishing, guaranteeing that a control command is never observed without a
corresponding durable record.

## Termination Semantics

### Inline vs isolate handlers

Stem can execute tasks either inline (inside the worker's main isolate) or in a
dedicated child isolate when a handler exposes an `isolateEntrypoint`. Inline
handlers share the worker's event loop and therefore run cooperatively: the
worker can interrupt them directly at the next checkpoint. Isolate handlers run
in separate Dart isolates; they communicate with the worker only when they send
control signals (heartbeat, lease extension, or progress). This distinction is
important for revokes because it determines how quickly the worker can apply a
`--terminate` request.

Docs can render multi-file examples using the `:::tabs`/`:::tab` directives
introduced in this update. Each tab accepts `label`/`value` attributes and code
blocks may add `title="path/to/file.dart"` metadata to display filenames.

:::tabs
:::tab{label="Inline handler"}
```dart title="tasks/inline_report_task.dart"
// Inline handler: no isolate entrypoint provided, so the worker executes it
// inside the main isolate.
class InlineReportTask implements TaskHandler<void> {
  @override
  String get name => 'tasks.inline-report';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 0);

  // The worker calls this directly. Any heartbeat/progress invocation happens
  // in the same isolate as the worker.
  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    for (final chunk in args['chunks'] as List<String>) {
      await processChunk(chunk);
      context.heartbeat();
    }
  }
}
```
:::

:::tab{label="Isolate handler"}
```dart title="tasks/image_render_task.dart"
// Isolate handler: returns a non-null isolateEntrypoint. The worker spins up a
// TaskIsolatePool and invokes the entrypoint in a dedicated isolate.
class ImageRenderTask implements TaskHandler<void> {
  @override
  String get name => 'tasks.render-image';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 0);

  // Non-null => worker uses isolate pool.
  @override
  TaskEntrypoint? get isolateEntrypoint => renderImageEntrypoint;

  // Optional: enqueue pre/post work that still runs inline (e.g. validate args)
  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {}
}

Future<void> renderImageEntrypoint(
  TaskInvocationContext ctx,
  Map<String, Object?> args,
) async {
  final tiles = args['tiles'] as List<ImageTile>;
  for (var i = 0; i < tiles.length; i++) {
    await renderTile(tiles[i]);

    if (i % 5 == 0) {
      ctx.heartbeat();
      ctx.progress(i / tiles.length);
    }
  }
}
```
:::
:::

The `isolateEntrypoint` must be a top-level or static function so it can be
serialized across isolates. Returning `null` keeps execution inline.

`stem worker revoke` accepts `--terminate` to request that active tasks stop as
soon as the worker reaches a safe checkpoint. Inline handlers (tasks executed in
the coordinator isolate) will throw a `TaskRevokedException` the next time they
call `TaskContext.heartbeat`, `extendLease`, or `progress`, causing the worker to
acknowledge the delivery as cancelled. Tasks running inside isolated executors
continue until they report back (heartbeat/lease/progress) or exit on their own;
termination is best-effort and relies on task code to emit those signals.

Operators should pair `--terminate` with observability: `stem worker inspect`
shows inflight tasks that still need to quiesce. If a task does not emit
heartbeats, consider adding them or implementing explicit cancellation logic in
handlers.

### Cooperative checkpoints for isolate handlers

Isolate entrypoints receive a `TaskInvocationContext` and must emit cooperative
signals so the worker can interrupt long-running work. Ensure the entrypoint
invokes at least one of the following inside any loop or lengthy section:

- `context.heartbeat()`
- `context.extendLease(duration)`
- `context.progress(percent, data: {...})`

Each helper throws `TaskRevokedException` when a terminate revoke is in effect,
allowing the handler to unwind quickly. A common pattern is to heartbeat every
few iterations or after each unit of work:

```dart
Future<void> crunch(TaskInvocationContext ctx, Map<String, Object?> args) async {
  final items = args['items'] as List<Object?>;
  for (var i = 0; i < items.length; i++) {
    await process(items[i]);

    if (i % 10 == 0) {
      ctx.heartbeat(); // throws if revoked with --terminate
      ctx.progress(i / items.length);
    }
  }
}
```

For CPU-bound workloads, insert an `await Future<void>.delayed(...)` or split the
loop into batches so the isolate yields periodically. Without these checkpoints
the worker cannot pre-empt the task until it naturally returns.
