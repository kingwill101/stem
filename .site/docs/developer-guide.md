---
id: developer-guide
title: Developer Guide
sidebar_label: Developer Guide
---

Stem is a spec-driven background job platform for Dart. This guide walks through installing Stem, registering tasks, enqueueing work, and operating a worker/beat process locally.

## Prerequisites

- Dart 3.3+
- Redis 7+ (for production-style testing)
- Node.js 18+ (for the CLI and Docusaurus docs site)

The repository already contains in-memory adapters for local experimentation, so you can start without Redis while learning the APIs.

## Installing Stem

Add Stem to your Dart package:

```bash
dart pub add stem
```

The package exposes contracts, registry helpers, broker/backends, and CLI utilities from `package:stem/stem.dart`.

## Registering Tasks

Create a task handler by implementing `TaskHandler` or using `FunctionTaskHandler` for isolate-friendly entrypoints.

```dart
import 'package:stem/stem.dart';

class EmailTask implements TaskHandler<void> {
  @override
  String get name => 'email.send';

  @override
  TaskOptions get options => const TaskOptions(
        maxRetries: 5,
        softTimeLimit: Duration(seconds: 10),
        hardTimeLimit: Duration(seconds: 20),
      );

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    // TODO: integrate with email provider
    context.progress(0.5);
    context.progress(1.0);
  }
}
```

Register handlers with `SimpleTaskRegistry` and share the registry with both the producer and worker processes.

```dart
final registry = SimpleTaskRegistry()
  ..register(EmailTask());
```

## Configuring a Stem Client

Construct a `StemConfig` from environment variables or instantiate manually. The config controls broker/backend URLs, default queue, prefetch multiplier, and default retry limit.

```dart
final config = StemConfig.fromEnvironment();
final broker = await RedisStreamsBroker.connect(config.brokerUrl);
final backend = await RedisResultBackend.connect(config.resultBackendUrl!);
final stem = Stem(broker: broker, registry: registry, backend: backend);
```

For quick experiments you can rely on the in-memory implementations:

```dart
final broker = InMemoryRedisBroker();
final backend = InMemoryResultBackend();
```

## Enqueueing Tasks

```dart
final taskId = await stem.enqueue(
  'email.send',
  args: {'recipient': 'ops@example.com'},
  headers: {'tenant': 'billing'},
  options: const TaskOptions(queue: 'notifications'),
);
print('queued task $taskId');
```

Stem persists the envelope via the broker and records an initial `queued` status in the result backend.

## Running a Worker

Workers coordinate task execution, isolate pooling, heartbeats, and retry workflows.

```dart
final worker = Worker(
  broker: broker,
  registry: registry,
  backend: backend,
  consumerName: 'worker-1',
  concurrency: 4,
  prefetchMultiplier: 2,
);

await worker.start();
```

Behind the scenes the worker maintains a task isolate pool, enforces soft/hard time limits, emits heartbeats, and records task lifecycle metrics.

Use `await worker.shutdown()` for graceful termination.

## Scheduling Tasks

Stem ships a Beat scheduler that reads schedule definitions from Redis. For local development you can use the `stem schedule` CLI subcommands to manage entries backed by the in-repo schedule store.

```bash
# Inspect current schedules
stem schedule list

# Add a cron entry
stem schedule add --id cleanup --task maintenance.cleanup --spec "0 2 * * *"
```

## CLI Utilities

The `stem` CLI wraps observability commands, schedule helpers, and DLQ management:

```bash
stem observe metrics
stem dlq list --queue default
stem dlq replay --queue default --limit 5 --yes
```

The CLI automatically reads connection details from the standard `StemConfig` environment variables.

## Example Application

Two runnable examples live under `examples/`:

- `examples/monolith_service` – a single Dart service exposing an HTTP endpoint that enqueues tasks and starts an in-process worker & beat.
- `examples/microservice` – separate enqueue API and worker package communicating through Redis.

See each example’s README for setup commands. The repository CI runs their smoke tests to guarantee they remain functional.

## Next Steps

- Read the [Operations Guide](operations-guide.md) for deployment and troubleshooting practices.
- Review the [Scaling Playbook](scaling-playbook.md) when planning horizontal expansion.
- Explore the `test/` suite for practical patterns around retries, DLQ handling, and isolate-aware task execution.
