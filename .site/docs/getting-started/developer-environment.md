---
title: Connect to Infrastructure
sidebar_label: Infrastructure
sidebar_position: 3
slug: /getting-started/developer-environment
---

Graduate from the in-memory demo to a multi-process setup backed by Redis or
Postgres. You will run workers, Beat, and the CLI in separate terminals while
exploring routing, broadcast delivery, and canvas composition with persistent
storage.

## 1. Run Redis and Postgres Locally

Docker is the fastest way to spin up dependencies:

```bash
# Redis Streams for broker, locks, rate limiting, and schedules.
docker run --rm -p 6379:6379 redis:7-alpine

# Postgres for durable task results or schedule storage (optional now, useful later).
docker run --rm -p 5432:5432 \
  -e POSTGRES_PASSWORD=postgres \
  postgres:14
```

Export the connection details so producers, workers, and Beat share them:

```bash
export STEM_BROKER_URL=redis://localhost:6379
export STEM_RESULT_BACKEND_URL=redis://localhost:6379/1
export STEM_SCHEDULE_STORE_URL=redis://localhost:6379/2
export STEM_CONTROL_NAMESPACE=stem
```

## 2. Bootstrap Stem Config

Use `StemConfig.fromEnvironment()` to hydrate adapters from the environment and
share them across your app. Split the bootstrap into smaller steps so each
piece is easy to scan and reuse:

### Load configuration

```dart title="lib/stem_bootstrap.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/developer_environment.dart#dev-env-config

```

### Connect adapters

```dart title="lib/stem_bootstrap.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/developer_environment.dart#dev-env-adapters

```

### Create the Stem producer

```dart title="lib/stem_bootstrap.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/developer_environment.dart#dev-env-stem

```

### Create the worker

```dart title="lib/stem_bootstrap.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/developer_environment.dart#dev-env-worker

```

Together, these steps give you access to routing, rate limiting, revoke
storage, and queue configuration—all backed by Redis.

## 3. Launch Workers, Beat, and Producers

With the environment configured, run Stem components from separate terminals:

```bash
# Terminal 1 — run a worker process (set STEM_WORKER_COMMAND or pass --command).
export STEM_WORKER_COMMAND="dart run bin/worker.dart"
stem worker multi start alpha --queue default --queue reports --queue emails

# Terminal 2 — apply schedules and run Beat (Dart entrypoint).
stem schedule apply --file config/schedules.json --yes
stem schedule list
dart run packages/stem/example/scheduler_observability/bin/beat.dart
```

Use a producer entrypoint to enqueue work:

```dart title="lib/producer.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/producer.dart#producer-redis

```

Routing configuration supports default queue aliases, glob-based routing
rules, and broadcast channels. A minimal `config/routing.yaml` might look like:

```yaml title="config/routing.yaml"
default_queue: critical
queues:
  reports:
    routing_key: reports.generate
    priority_range: [2, 7]
  emails:
    routing_key: billing.email-*
broadcasts:
  maintenance:
    delivery: fanout
```

Stem clamps priorities to queue-defined ranges and publishes broadcast tasks to
all subscribed workers exactly once per acknowledgement window.

## 4. Coordinate Work with Canvas and Result Backend

Now that Redis backs the result store, you can orchestrate more complex
pipelines and query progress from any process:

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/developer_environment.dart#dev-env-canvas

```

Later, you can monitor status from any machine:

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/developer_environment.dart#dev-env-status

```

## 5. Listen to Signals for Cross-Cutting Integrations

Signals surface lifecycle milestones that you can pipe into analytics or
incident tooling:

```dart title="lib/signals.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/developer_environment.dart#dev-env-signals

```

Call `installSignalHandlers()` during bootstrap before workers or producers
start emitting events.

## 6. What’s Next

- Keep the infrastructure running and head to
  [Observe & Operate](./observability-and-ops.md) to enable telemetry, inspect
  heartbeats, replay DLQs, and issue remote control commands.
- Browse the runnable examples under `examples/` for Redis/Postgres,
  mixed-cluster, autoscaling, scheduler observability, and signing-key rotation
  drills you can adapt to your environment.
