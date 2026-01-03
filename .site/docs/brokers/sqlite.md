---
title: SQLite Adapter
sidebar_label: SQLite
sidebar_position: 2
slug: /brokers/sqlite
---

Stem ships a SQLite adapter in `stem_sqlite` that implements both the broker
and result backend contracts. It is designed for local development, demo
environments, and single-node deployments that want a zero-infra dependency.

## When to use SQLite

Use SQLite when you:

- Need a **single-process** or **single-host** deployment.
- Want a **zero-infrastructure** dev/test broker + backend.
- Prefer a local file-backed queue for demos or smoke tests.

Avoid SQLite when you need multi-host scaling, broadcast control channels, or
high-throughput workloads. Redis or Postgres are better fits in production.

## Install

Add the adapter package:

```yaml
dependencies:
  stem_sqlite: ^0.1.0-dev
```

## Quick start (broker)

```dart title="brokers.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/brokers.dart#brokers-sqlite

```

## Quick start (result backend)

```dart title="persistence.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/persistence.dart#persistence-backend-sqlite

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

Migrations run automatically on first open; keep the database file on local
disk and allow the process to create the file if it does not exist.

## Recommended layout (separate DB files)

SQLite uses WAL and only allows **one writer at a time**. To avoid lock
contention:

- **Use separate DB files** for the broker and backend.
- **Keep producers off the backend** (let workers be the only writers).
- **Do not share a single SQLite file** between broker and backend.

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

- **No broadcast channels** (worker control commands won’t work).
- **Single-queue subscriptions only** (one queue per worker subscription).
- **Polling-based delivery** (latency depends on `pollInterval`).
- **Single-writer constraint** (plan your processes and DB files accordingly).

If you need broadcast control, multi-queue consumption, or multi-host scaling,
use Redis or Postgres instead.

## Examples

- `packages/stem/example/task_context_mixed` – TaskContext/TaskInvocationContext
  enqueue patterns on SQLite.
- `packages/stem/example/workflows/sqlite_store.dart` – workflow state stored
  in SQLite.
- `packages/stem_sqlite/example/stem_sqlite_example.dart` – adapter smoke test.
