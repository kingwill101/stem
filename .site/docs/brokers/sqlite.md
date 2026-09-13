---
title: SQLite Adapter
sidebar_label: SQLite
sidebar_position: 2
slug: /brokers/sqlite
---

Stem ships a SQLite adapter in `stem_sqlite` that implements broker, result
backend, and revoke store contracts. It is designed for local development, demo
environments, and single-node deployments that want a zero-infra dependency.

## When to use SQLite

Use SQLite when you:

- Need a **single-process** or **single-host** deployment.
- Want a **zero-infrastructure** dev/test broker + backend.
- Prefer a local file-backed queue for demos or smoke tests.

Avoid SQLite when you need multi-host scaling or cross-process broadcast
control. Delivery is polling-based and SQLite permits one writer at a time, so
Redis or Postgres are usually better fits for high-throughput production
workloads.

## Install

Add the adapter package using the version resolved for your release. The
repository checkout currently declares `0.3.0`, but that does not establish
what is published on pub:

```yaml
dependencies:
  stem_sqlite: any
```

Prefer `dart pub add stem_sqlite` for a published application, or use a
`path:` dependency while evaluating this checkout.

## Quick start (broker)

```dart title="brokers.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/brokers.dart#brokers-sqlite

```

## Quick start (result backend)

```dart title="persistence.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/persistence.dart#persistence-backend-sqlite

```

## Quick start (revoke store)

```dart title="persistence.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/persistence.dart#persistence-revoke-store-sqlite

```

## Configuration knobs

SQLite adapters expose the same tuning hooks as other brokers/backends:

**Broker options**
- `namespace`: logical namespace for queue rows.
- `defaultVisibilityTimeout`: lease duration before re-delivery.
- `pollInterval`: how often workers poll for due jobs.
- `sweeperInterval`: how often to clear expired locks.
- `deadLetterRetention`: how long to keep dead letter rows.

**Result backend options**
- `namespace`: logical namespace for task result rows.
- `defaultTtl`: how long task results are retained by default.
- `groupDefaultTtl`: TTL for group/chord metadata.
- `heartbeatTtl`: TTL for worker heartbeat rows.
- `cleanupInterval`: how frequently expired rows are cleaned up.

These options are passed to `SqliteBroker.open(...)` and
`SqliteResultBackend.open(...)`.

Opening `SqliteBroker` or `SqliteResultBackend` runs the adapter migrations.
Keep the database file on local disk and allow the process to create it if it
does not exist.

## Recommended layout (separate DB files)

SQLite uses WAL and only allows **one writer at a time**. To avoid lock
contention:

- **Use separate DB files** for the broker and backend.
- **Keep producers off the backend** (let workers be the only writers).
- Sharing a file is supported, but separate files are the recommended layout:
  it reduces writer contention between queue settlement and result writes.

Stem serializes its own transactional mutations when multiple handles in the
same isolate point at the same file, preventing savepoint corruption and
in-process writer races. This coordination does not cover unrelated processes
or tools opening the file, and it cannot turn SQLite into a multi-host queue.
Use separate files when throughput or process isolation matters.

A simple layout:

```
./stem_broker.sqlite   # broker only
./stem_backend.sqlite  # result backend only
```

The `task_context_mixed` example defaults to separate files and exposes:

- `STEM_SQLITE_BROKER_PATH`
- `STEM_SQLITE_BACKEND_PATH`

## Running with native assets

The `sqlite3` package uses native assets. For stable behavior, build CLI
bundles and run the compiled binary:

```bash
cd packages/stem/example/task_context_mixed

dart build cli -t bin/worker.dart -o build/worker
dart build cli -t bin/enqueue.dart -o build/enqueue

build/worker/bundle/bin/worker
build/enqueue/bundle/bin/enqueue
```

## Adapter limitations

SQLite brokers are intentionally minimal:

- **Broadcast fan-out is in-process only** (worker control commands across
  processes are not supported).
- **Single-queue subscriptions only** (one queue per worker subscription).
- **Polling-based delivery** (latency depends on `pollInterval`).
- **Single-writer constraint** (plan your processes and DB files accordingly).
- Stem coordinates in-process writes across its broker, backend, workflow, and
  control handles, but external writers and separate processes still need
  SQLite-compatible locking discipline.
- SQLite is local persistence, not a mobile OS background scheduler. A platform
  callback must reopen the app and explicitly start or recover work.

If you need cross-process broadcast control or multi-host scaling, use Redis or
Postgres instead.

## Examples

- `packages/stem/example/task_context_mixed` – TaskContext/TaskInvocationContext
  enqueue patterns on SQLite.
- `packages/stem/example/workflows/sqlite_store.dart` – workflow state stored
  in SQLite.
- `packages/stem_sqlite/example/stem_sqlite_example.dart` – adapter smoke test.
