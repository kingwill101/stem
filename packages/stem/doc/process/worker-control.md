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
| `stem worker shutdown` | Requests warm/soft/hard shutdown via the control plane. |
| `stem worker multi` | Manage multiple worker processes (start/stop/restart/status). |
| `stem worker healthcheck` | Probe worker processes for readiness/liveness. |
| `stem worker diagnose` | Run local diagnostics for pid/log/env configuration issues. |

Use `--namespace` to target non-default control namespaces; omit
`--worker` to broadcast to every worker.

## Autoscaling Concurrency

Workers can now autoscale their isolate pools between configurable minimum and
maximum bounds. Pass a `WorkerAutoscaleConfig` when constructing the worker to
enable the evaluator:

```dart
final worker = Worker(
  broker: broker,
  registry: registry,
  backend: backend,
  queue: 'critical',
  concurrency: 12, // maximum
  autoscale: const WorkerAutoscaleConfig(
    enabled: true,
    minConcurrency: 2,
    maxConcurrency: 12,
    scaleUpStep: 2,
    scaleDownStep: 1,
    idlePeriod: Duration(seconds: 45),
    tick: Duration(milliseconds: 250),
  ),
);
```

The autoscaler samples `broker.pendingCount(queue)` alongside the worker's
inflight count to decide when to scale. Metrics expose the current setting via
`stem.worker.concurrency`, and `stem worker stats --json` now includes
`activeConcurrency` alongside the configured maximum. Broadcast control commands
continue to operate while autoscaling; no restarts are required.

## CLI Multi-Instance Management

Use `stem worker multi` to orchestrate operating-system processes for one or
many worker nodes. Its templated paths support the same placeholders as the
service files (`%n` node, `%h` hostname, `%I` index, `%d` timestamp), and the
command defaults to the value of `STEM_WORKER_COMMAND` from the environment or
the loaded env file.

```bash
export STEM_WORKER_COMMAND="/usr/bin/stem-worker"
stem worker multi start alpha beta \
  --pidfile=/var/run/stem/%n.pid \
  --logfile=/var/log/stem/%n.log \
  --env-file=/etc/stem/stem.env

# Later
stem worker multi status alpha beta --pidfile=/var/run/stem/%n.pid
stem worker multi stop alpha beta --pidfile=/var/run/stem/%n.pid
```

Additional arguments can be provided with `--command` (repeatable) or
`--command-line "cmd --flags"`. The CLI creates PID/log directories as needed
and exports helpful metadata (`STEM_WORKER_NODE`, `STEM_WORKER_PIDFILE`,
`STEM_WORKER_LOGFILE`) to the launched process.

Use `--queue` (repeatable) to subscribe nodes to specific queues and
`--broadcast` to join broadcast channels. The CLI resolves aliases using the
routing configuration referenced by `STEM_ROUTING_CONFIG` and exports
`STEM_WORKER_QUEUES` / `STEM_WORKER_BROADCASTS` for the child process. When
these options are omitted the worker falls back to the default queue defined in
`StemConfig`.

## Worker Healthcheck

Use `stem worker healthcheck` inside systemd `ExecStartPost=`, Kubernetes probes,
or shell scripts to determine whether a worker process is running:

```bash
stem worker healthcheck \
  --node alpha \
  --pidfile=/var/run/stem/alpha.pid \
  --logfile=/var/log/stem/alpha.log \
  --json
```

Exit code `0` indicates the PID file exists and the process is alive. The JSON
payload includes the pid, timestamp captured from the PID file, and the uptime
in seconds.

## Worker Diagnostics

`stem worker diagnose` performs common checks (PID/log directories, stale PID
files, environment file parsing) to help troubleshoot daemonization issues:

```bash
stem worker diagnose \
  --pidfile=/var/run/stem/alpha.pid \
  --logfile=/var/log/stem/alpha.log \
  --env-file=/etc/stem/stem.env
```

Warnings and errors are printed for missing directories, unparseable PIDs, and
other configuration gaps. Use `--json` when integrating with tooling.

## Routing Configuration Helpers

Inspect the active routing file with `stem routing dump`. Pass `--json` to
emit the raw map or `--sample` to print a starter skeleton suitable for new
deployments.

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

If you are using `FunctionTaskHandler`, set `runInIsolate: false` or use the
`FunctionTaskHandler.inline(...)` factory to force inline execution when the
entrypoint captures non-sendable state.

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
`FunctionTaskHandler.inline(...)` (or `runInIsolate: false`) is the easiest way
to keep closure-based handlers inline.

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

## Shutdown Modes and Lifecycle Guards

`stem worker shutdown` lets operators request warm, soft, or hard shutdown over
the control channel:

- **Warm** stops new deliveries and waits for in-flight tasks to finish.
- **Soft** issues `terminate=true` revocations and, after the configured grace
  period, escalates to a hard stop if tasks are still running.
- **Hard** immediately requeues active deliveries and tears down the isolate
  pool.

Workers install sensible signal defaults (`SIGTERM` → warm, `SIGINT` → soft,
`SIGQUIT` → hard) which can be disabled via
`WorkerLifecycleConfig(installSignalHandlers: false)`. Lifecycle guards also
support recycling child isolates by count or memory usage:

```dart
final worker = Worker(
  /* ... */,
  lifecycle: const WorkerLifecycleConfig(
    maxTasksPerIsolate: 500,
    maxMemoryPerIsolateBytes: 512 * 1024 * 1024, // 512 MiB
  ),
);
```

When a threshold is exceeded the worker drains the task, logs the recycle, and
starts a fresh isolate before accepting additional work.

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
