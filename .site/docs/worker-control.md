---
id: worker-control
title: Worker Control
sidebar_label: Worker Control
---

Stem exposes a broker-backed control plane so operators can inspect, revoke, and
coordinate workers without restarts. This guide walks through the CLI surface,
revocation durability, and termination semantics for inline vs isolate handlers.

## CLI Overview

| Command | Purpose |
| ------- | ------- |
| `stem worker ping` | Broadcast a ping and aggregate worker responses. |
| `stem worker inspect` | List in-flight tasks (and optional revoke cache) per worker. |
| `stem worker stats` | Summarize inflight counts, queue depth, and metadata. |
| `stem worker revoke` | Persist revocations and broadcast terminate/best-effort revokes. |
| `stem worker status` | Stream heartbeats or snapshot the backend (existing command). |

Use `--namespace` to target non-default control namespaces. Omitting `--worker`
broadcasts to every worker. All commands honour the same environment variables as
`stem health` (`STEM_BROKER_URL`, `STEM_RESULT_BACKEND_URL`, TLS/signing flags).

### Quick Examples

```bash
# Ping a subset of workers by identifier
stem worker ping --worker worker-a --worker worker-b

# Inspect all workers (JSON output)
stem worker inspect --json

# Revoke a task and request termination
stem worker revoke --task 1761057... --terminate
```

## Persistent Revokes

Revocations are durable so new workers or restarts continue honouring them. The
CLI resolves the backing store in this order:

1. `STEM_REVOKE_STORE_URL`
2. `STEM_RESULT_BACKEND_URL`
3. `STEM_BROKER_URL`

Supported schemes: Redis (`redis://`, `rediss://`), Postgres (`postgres://`,
`postgresql://`), a newline-delimited file (`file:///path/to/revokes.stem` or
bare path), and in-memory (`memory://` – useful for tests). Workers hydrate the
revocation cache at startup, prune expired records, and apply new control
messages. The CLI writes through the store *before* broadcasting control
messages to guarantee durability precedes visibility.

## Termination Semantics

### Inline vs isolate handlers

Stem executes tasks either inline (worker main isolate) or in dedicated child
isolates when a handler exposes an `isolateEntrypoint`. Inline handlers share the
worker event loop and can be interrupted immediately at the next checkpoint.
Isolate handlers communicate with the worker only when they emit control signals
(heartbeat, lease extension, progress). That difference governs how quickly a
`--terminate` revoke takes effect.

### Inline handler example

```dart title="tasks/inline_report_task.dart"
class InlineReportTask implements TaskHandler<void> {
  @override
  String get name => 'tasks.inline-report';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 0);

  // Runs inside the worker isolate. Heartbeats/progress immediately respect
  // terminate revokes because they execute in the same isolate.
  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    for (final chunk in args['chunks'] as List<String>) {
      await processChunk(chunk);
      context.heartbeat();
    }
  }
}
```

### Isolate handler example

```dart title="tasks/image_render_task.dart"
class ImageRenderTask implements TaskHandler<void> {
  @override
  String get name => 'tasks.render-image';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 0);

  // Non-null isolateEntrypoint => worker uses the TaskIsolatePool.
  @override
  TaskEntrypoint? get isolateEntrypoint => renderImageEntrypoint;

  // Inline pre/post work (validation, logging) still runs in the worker isolate.
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

`stem worker revoke --terminate` throws `TaskRevokedException` the next time an
inline handler calls `TaskContext.heartbeat`, `extendLease`, or `progress`,
allowing the worker to cancel and record the task as cancelled. Isolate handlers
must emit cooperative checkpoints (heartbeat/lease/progress) to be interrupted;
otherwise they finish naturally.

### Cooperative checkpoints for isolate handlers

Make sure isolate entrypoints call one of the cooperative helpers inside any
long-running loop. Each helper throws `TaskRevokedException` when a terminate
revoke is pending, which lets the handler fail fast.

```dart title="tasks/crunch.dart"
Future<void> crunch(TaskInvocationContext ctx, Map<String, Object?> args) async {
  final items = args['items'] as List<Object?>;
  for (var i = 0; i < items.length; i++) {
    await process(items[i]);

    if (i % 10 == 0) {
      ctx.heartbeat();             // Throws if revoked with --terminate
      ctx.progress(i / items.length);
    }
  }
}
```

For CPU-bound workloads, batch work or insert `await Future<void>.delayed(...)`
so the isolate yields periodically. Without checkpoints the worker cannot
pre-empt the task until it returns on its own.

Operators should pair `--terminate` with `stem worker inspect` to monitor
inflight tasks that still need to quiesce. If a handler never emits heartbeats,
add them or implement explicit cancellation logic.

## Configuration Summary

| Variable | Purpose |
| --- | --- |
| `STEM_REVOKE_STORE_URL` | Override the revoke store target (defaults to backend or broker). |
| `STEM_CONTROL_NAMESPACE` | Override the control namespace (defaults to heartbeat namespace). |
| `STEM_WORKER_NAMESPACE` | Logical grouping for worker IDs/queues. |
| `STEM_CONTROL_TIMEOUT` | Default control command timeout (e.g. `5s`). |

Set `STEM_REVOKE_STORE_URL` to the datastore you want to back revocations. For
example, to use Postgres alongside the result backend:

```bash
export STEM_REVOKE_STORE_URL=postgres://stem:secret@db:5432/stem
```

## Additional Resources

- [Operations Guide](./operations-guide.md) – configuration, monitoring, and
  day-to-day runbooks (includes a Worker Control section).
- [Scaling Playbook](./scaling-playbook.md) – autoscaling and capacity planning.
- `stem worker --help` – built-in CLI usage for each subcommand.
