[![pub package](https://img.shields.io/pub/v/stem.svg)](https://pub.dev/packages/stem)
[![Dart](https://img.shields.io/badge/dart-%3E%3D3.9.0-blue.svg)](https://dart.dev/)
[![License](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)
[![Build Status](https://github.com/kingwill101/stem/workflows/ci/badge.svg)](https://github.com/kingwill101/stem/actions)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow.svg)](https://www.buymeacoffee.com/kingwill101)

# Stem

 Stem is a Dart-native background job platform. It gives you Celery-style
task execution with a Dart-first API, Redis Streams integration, retries,
scheduling, observability, and security tooling-all without leaving the Dart
ecosystem.

## Install

```bash
dart pub add stem           # core runtime APIs
dart pub add stem_redis     # Redis broker + result backend
dart pub add stem_postgres  # (optional) Postgres broker + backend
dart pub global activate stem_cli
```

Add the pub-cache bin directory to your `PATH` so the `stem_cli` tool is available:

```bash
export PATH="$HOME/.pub-cache/bin:$PATH"
stem --help
```

## Quick Start

### Direct enqueue (map-based)

```dart
import 'dart:async';
import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

class HelloTask implements TaskHandler<void> {
  @override
  String get name => 'demo.hello';

  @override
  TaskOptions get options => const TaskOptions(
        queue: 'default',
        maxRetries: 3,
        rateLimit: '10/s',
        visibilityTimeout: Duration(seconds: 60),
      );

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    final who = args['name'] as String? ?? 'world';
    print('Hello $who (attempt ${context.attempt})');
  }
}

Future<void> main() async {
  final registry = SimpleTaskRegistry()..register(HelloTask());
  final broker = await RedisStreamsBroker.connect('redis://localhost:6379');
  final backend = await RedisResultBackend.connect('redis://localhost:6379/1');

  final stem = Stem(broker: broker, registry: registry, backend: backend);
  final worker = Worker(broker: broker, registry: registry, backend: backend);

  unawaited(worker.start());
  await stem.enqueue('demo.hello', args: {'name': 'Stem'});
  await Future<void>.delayed(const Duration(seconds: 1));
  await worker.shutdown();
  await broker.close();
  await backend.close();
}
```

### Typed helpers with `TaskDefinition`

Use the new typed wrapper when you want compile-time checking and shared metadata:

```dart
class HelloTask implements TaskHandler<void> {
  static final definition = TaskDefinition<HelloArgs, void>(
    name: 'demo.hello',
    encodeArgs: (args) => {'name': args.name},
    metadata: TaskMetadata(description: 'Simple hello world example'),
  );

  @override
  String get name => 'demo.hello';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 3);

  @override
  TaskMetadata get metadata => definition.metadata;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    final who = args['name'] as String? ?? 'world';
    print('Hello $who (attempt ${context.attempt})');
  }
}

class HelloArgs {
  const HelloArgs({required this.name});
  final String name;
}

Future<void> main() async {
  final registry = SimpleTaskRegistry()..register(HelloTask());
  final broker = await RedisStreamsBroker.connect('redis://localhost:6379');
  final backend = await RedisResultBackend.connect('redis://localhost:6379/1');

  final stem = Stem(broker: broker, registry: registry, backend: backend);
  final worker = Worker(broker: broker, registry: registry, backend: backend);

  unawaited(worker.start());
  await stem.enqueueCall(
    HelloTask.definition(const HelloArgs(name: 'Stem')),
  );
  await Future<void>.delayed(const Duration(seconds: 1));
  await worker.shutdown();
  await broker.close();
  await backend.close();
}
```

You can also build requests fluently with the `TaskEnqueueBuilder`:

```dart
final taskId = await TaskEnqueueBuilder(
  definition: HelloTask.definition,
  args: const HelloArgs(name: 'Tenant A'),
)
  ..header('x-tenant', 'tenant-a')
  ..priority(5)
  ..delay(const Duration(seconds: 30))
  .enqueueWith(stem);
```

### Bootstrap helpers

Spin up a full runtime in one call using the bootstrap APIs:

```dart
final app = await StemWorkflowApp.inMemory(
  flows: [
    Flow(
      name: 'demo.workflow',
      build: (flow) {
        flow.step('hello', (ctx) async => 'done');
      },
    ),
  ],
);

final runId = await app.startWorkflow('demo.workflow');
final state = await app.waitForCompletion(runId);
print(state?.status); // WorkflowStatus.completed

await app.shutdown();
```

### Workflow script facade

Prefer the high-level `WorkflowScript` facade when you want to author a
workflow as a single async function. The facade wraps `FlowBuilder` so your
code can `await script.step`, `await step.sleep`, and `await step.awaitEvent`
while retaining the same durability semantics (checkpoints, resume payloads,
auto-versioning) as the lower-level API:

```dart
final app = await StemWorkflowApp.inMemory(
  scripts: [
    WorkflowScript(
      name: 'orders.workflow',
      run: (script) async {
        final checkout = await script.step('checkout', (step) async {
          return await chargeCustomer(step.params['userId'] as String);
        });

        await script.step('poll-shipment', (step) async {
          final resume = step.takeResumeData();
          if (resume != true) {
            await step.sleep(const Duration(seconds: 30));
            return 'waiting';
          }
          final status = await fetchShipment(checkout.id);
          if (!status.isComplete) {
            await step.sleep(const Duration(seconds: 30));
            return 'waiting';
          }
          return status.value;
        }, autoVersion: true);

        final receipt = await script.step('notify', (step) async {
          await sendReceiptEmail(checkout);
          return 'emailed';
        });

        return receipt;
      },
    ),
  ],
);
```

Inside a script step you can access the same metadata as `FlowContext`:

- `step.previousResult` contains the prior step’s persisted value.
- `step.iteration` tracks the current auto-version suffix when
  `autoVersion: true` is set.
- `step.idempotencyKey('scope')` builds stable outbound identifiers.
- `step.takeResumeData()` surfaces payloads from sleeps or awaited events so
  you can branch on resume paths.

### Durable workflow semantics

- Steps may run multiple times. The runtime replays a step from the top after
  every suspension (sleep, awaited event, rewind) and after worker crashes, so
  handlers must be idempotent.
- Event waits are durable watchers. When a step calls `awaitEvent`, the runtime
  registers the run in the store so the next emitted payload is persisted
  atomically and delivered exactly once on resume. Operators can inspect
  suspended runs via `WorkflowStore.listWatchers` or `runsWaitingOn`.
- Checkpoints act as heartbeats. Every successful `saveStep` refreshes the run's
  `updatedAt` timestamp so operators (and future reclaim logic) can distinguish
  actively-owned runs from ones that need recovery.
- Use `ctx.takeResumeData()` to detect whether a step is resuming. Call it at
  the start of the handler and branch accordingly.
- When you suspend, provide a marker in the `data` payload so the resumed step
  can distinguish the wake-up path. For example:

  ```dart
  final resume = ctx.takeResumeData();
  if (resume != true) {
    ctx.sleep(const Duration(milliseconds: 200));
    return null;
  }
  ```

- Awaited events behave the same way: the emitted payload is delivered via
  `takeResumeData()` when the run resumes.
- Only return values you want persisted. If a handler returns `null`, the
  runtime treats it as "no result yet" and will run the step again on resume.
- Derive outbound idempotency tokens with `ctx.idempotencyKey('charge')` so
  retries reuse the same stable identifier (`workflow/run/scope`).
- Use `autoVersion: true` on steps that you plan to re-execute (e.g. after
  rewinding). Each completion stores a checkpoint like `step#0`, `step#1`, ... and
  the handler receives the current iteration via `ctx.iteration`.
- Set an optional `WorkflowCancellationPolicy` when starting runs to auto-cancel
  workflows that exceed a wall-clock budget or stay suspended beyond an allowed
  duration. When a policy trips, the run transitions to `cancelled` and the
  reason is surfaced via `stem wf show`.

```dart
flow.step(
  'process-item',
  autoVersion: true,
  (ctx) async {
    final iteration = ctx.iteration;
    final item = items[iteration];
    return await process(item);
  },
);

final runId = await runtime.startWorkflow(
  'demo.workflow',
  params: const {'userId': '42'},
  cancellationPolicy: const WorkflowCancellationPolicy(
    maxRunDuration: Duration(minutes: 15),
    maxSuspendDuration: Duration(minutes: 5),
  ),
);
```

Adapter packages expose typed factories (e.g. `redisBrokerFactory`,
`postgresResultBackendFactory`, `sqliteWorkflowStoreFactory`) so you can replace
drivers by importing the adapter you need.

## Features

- **Task pipeline** - enqueue with delays, priorities, idempotency helpers, and retries.
- **Workers** - isolate pools with soft/hard time limits, autoscaling, and remote control (`stem worker ping|revoke|shutdown`).
- **Scheduling** - Beat-style scheduler with interval/cron/solar/clocked entries and drift tracking.
- **Workflows** - Durable `Flow` runtime with pluggable stores (in-memory,
  Redis, Postgres, SQLite) and CLI introspection via `stem wf`.
- **Observability** - Dartastic OpenTelemetry metrics/traces, heartbeats, CLI inspection (`stem observe`, `stem dlq`).
- **Security** - Payload signing (HMAC or Ed25519), TLS automation scripts, revocation persistence.
- **Adapters** - In-memory drivers included here; Redis Streams and Postgres adapters ship via the `stem_redis` and `stem_postgres` packages.
- **Specs & tooling** - OpenSpec change workflow, quality gates (`tool/quality/run_quality_checks.sh`), chaos/regression suites.

## Documentation & Examples

- Full docs: [Full docs](.site/docs) (run `npm install && npm start` inside `.site/`).
- Guided onboarding: [Guided onboarding](.site/docs/getting-started/) (install → infra → ops → production).
- Examples (each has its own README):
- [workflows](example/workflows/) - end-to-end workflow samples (in-memory, sleep/event, SQLite, Redis). See `versioned_rewind.dart` for auto-versioned step rewinds.
- [cancellation_policy](example/workflows/cancellation_policy.dart) - demonstrates auto-cancelling long workflows using `WorkflowCancellationPolicy`.
- [rate_limit_delay](example/rate_limit_delay) - delayed enqueue, priority clamping, Redis rate limiter.
- [dlq_sandbox](example/dlq_sandbox) - dead-letter inspection and replay via CLI.
- [microservice](example/microservice), [monolith_service](example/monolith_service), [mixed_cluster](example/mixed_cluster) - production-style topologies.
- [unique_tasks](example/unique_tasks/unique_task_example.dart) - enables `TaskOptions.unique` with a shared lock store.
- [security examples](example/security/*) - payload signing + TLS profiles.
- [postgres_tls](example/postgres_tls) - Redis broker + Postgres backend secured via the shared `STEM_TLS_*` settings.
- [otel_metrics](example/otel_metrics) - OTLP collectors + Grafana dashboards.

## Running Tests Locally

Start the dockerised dependencies and export the integration variables before
invoking the test suite:

```bash
source packages/stem_cli/_init_test_env
dart test
```

The helper script launches `packages/stem_cli/docker/testing/docker-compose.yml`
(Redis + Postgres) and populates `STEM_TEST_*` environment variables needed by
the integration suites.

### Adapter Contract Tests

Stem ships a reusable adapter contract suite in
`packages/stem_adapter_tests`. Adapter packages (Redis broker/postgres
backend, SQLite adapters, and any future integrations) add it as a
`dev_dependency` and invoke `runBrokerContractTests` /
`runResultBackendContractTests` from their integration tests. The harness
exercises core behaviours-enqueue/ack/nack, dead-letter replay, lease
extension, result persistence, group aggregation, and heartbeat storage-so
all adapters stay aligned with the broker and result backend contracts. See
`test/integration/brokers/postgres_broker_integration_test.dart` and
`test/integration/backends/postgres_backend_integration_test.dart` for
reference usage.

### Testing helpers

Use `FakeStem` from `package:stem/stem.dart` in unit tests when you want to
record enqueued jobs without standing up brokers:

```dart
final fake = FakeStem();
await fake.enqueue('tasks.email', args: {'id': 1});
final recorded = fake.enqueues.single;
expect(recorded.name, 'tasks.email');
```
