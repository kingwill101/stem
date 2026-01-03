# Task Context Mixed Demo

This example demonstrates nested enqueueing from both `TaskContext` (inline
handlers) and `TaskInvocationContext` (inline + isolate entrypoints). It also
shows the full `TaskEnqueueOptions` / `TaskRetryPolicy` surface that mirrors
Celery-style `apply_async` controls.

## Requirements

- Dart 3.3+

## Run

Terminal 1 (worker):

```bash
cd packages/stem/example/task_context_mixed
dart pub get
dart run bin/worker.dart
```

Terminal 2 (enqueue):

```bash
dart run bin/enqueue.dart
```

For best results with `sqlite3` native assets, build the CLI binaries first
(`dart build cli`). The included `justfile` does this automatically.

Optional flags:

```bash
# Force the flaky task to fail so link_error triggers.
dart run bin/enqueue.dart --fail

# Reuse a task id to demonstrate overwrite semantics.
dart run bin/enqueue.dart --overwrite
```

## Configuration

- `STEM_SQLITE_BROKER_PATH` (optional): SQLite file for the broker.
- `STEM_SQLITE_BACKEND_PATH` (optional): SQLite file for the result backend.
- `STEM_SQLITE_PATH` (optional): Base path prefix used when the specific paths
  are not set (defaults to `task_context_mixed`, which becomes
  `task_context_mixed_broker.sqlite` and `task_context_mixed_backend.sqlite`).
- `WORKER_NAME` (optional): Worker name override.

## What it covers

- **TaskContext enqueue/spawn** from a `TaskHandler`.
- **TaskInvocationContext entrypoints** in both inline and isolate modes.
- **TaskRetryPolicy** and `TaskInvocationContext.retry` overrides.
- **TaskEnqueueOptions** fields including `taskId`, `eta`, `countdown`,
  `expires`, routing overrides, `timeLimit`, `softTimeLimit`, `serializer`,
  `compression`, `ignoreResult`, `shadow`, `replyTo`, publish retry policy,
  and `link`/`linkError` callbacks.

SQLite brokers ignore some routing hints (exchange/routing key) but they are
included here to mirror the Celery apply_async API surface. The demo uses
separate SQLite files for the broker and backend to avoid WAL contention and
keeps the producer disconnected from the backend (so only the worker writes
result state).

### Local build + just

```bash
just build
# In separate terminals:
just run-worker
just run-enqueue
# Or:
just tmux
```
