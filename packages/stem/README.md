[![pub package](https://img.shields.io/pub/v/stem.svg)](https://pub.dev/packages/stem)
[![Dart](https://img.shields.io/badge/dart-%3E%3D3.9.0-blue.svg)](https://dart.dev/)
[![License](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)
[![Build Status](https://github.com/kingwill101/stem/workflows/ci/badge.svg)](https://github.com/kingwill101/stem/actions)
[![Coverage](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/kingwill101/stem/main/packages/stem/coverage/coverage.json)](https://github.com/kingwill101/stem/actions/workflows/stem.yaml)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow.svg)](https://www.buymeacoffee.com/kingwill101)

<p align="center">
  <img src="../../.site/static/img/stem-logo.png" width="300" alt="Stem Logo" />
</p>

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

### StemClient entrypoint

Use a single entrypoint to share broker/backend/config between workers and
workflow apps.

```dart
import 'dart:async';
import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

class HelloTask implements TaskHandler<void> {
  @override
  String get name => 'demo.hello';

  @override
  TaskOptions get options => const TaskOptions(queue: 'default');

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    print('Hello from StemClient');
  }
}

Future<void> main() async {
  final client = await StemClient.create(
    broker: StemBrokerFactory.redis(url: 'redis://localhost:6379'),
    backend: StemBackendFactory.redis(url: 'redis://localhost:6379/1'),
    tasks: [HelloTask()],
  );

  final worker = await client.createWorker();
  unawaited(worker.start());

  await client.stem.enqueue('demo.hello');
  await Future<void>.delayed(const Duration(seconds: 1));

  await worker.shutdown();
  await client.close();
}
```

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

### Enqueue from inside a task

Handlers can enqueue follow-up work using `TaskContext.enqueue` and request
retries directly:

```dart
class ParentTask implements TaskHandler<void> {
  @override
  String get name => 'demo.parent';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 3);

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    await context.enqueue(
      'demo.child',
      args: {'id': 'child-1'},
      enqueueOptions: TaskEnqueueOptions(
        countdown: const Duration(seconds: 30),
        retry: true,
        retryPolicy: TaskRetryPolicy(backoff: true),
      ),
    );

    if (context.attempt == 0) {
      await context.retry(countdown: const Duration(seconds: 10));
    }
  }
}
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
final result = await app.waitForCompletion<String>(runId);
print(result?.value); // 'hello world'
print(result?.state.status); // WorkflowStatus.completed

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

        final receipt = await script.step<String>('notify', (step) async {
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

### Typed workflow completion

All workflow definitions (flows and scripts) accept an optional type argument
representing the value they produce. `StemWorkflowApp.waitForCompletion<T>`
exposes the decoded value along with the raw `RunState`, letting you work with
domain models without manual casts:

```dart
final runId = await app.startWorkflow('orders.workflow');
final result = await app.waitForCompletion<OrderReceipt>(
  runId,
  decode: (payload) => OrderReceipt.fromJson(payload! as Map<String, Object?>),
);
if (result?.isCompleted == true) {
  print(result!.value?.total);
} else if (result?.timedOut == true) {
  inspectSuspension(result?.state);
}
```

### Typed task completion

Producers can now wait for individual task results using `Stem.waitForTask<T>`
with optional decoders. The helper returns a `TaskResult<T>` containing the
underlying `TaskStatus`, decoded payload, and a timeout flag:

```dart
final taskId = await stem.enqueueCall(
  ChargeCustomer.definition.call(ChargeArgs(orderId: '123')),
);

final charge = await stem.waitForTask<ChargeReceipt>(
  taskId,
  decode: (payload) => ChargeReceipt.fromJson(
    payload! as Map<String, Object?>,
  ),
);
if (charge?.isSucceeded == true) {
  print('Captured ${charge!.value!.total}');
} else if (charge?.isFailed == true) {
  log.severe('Charge failed: ${charge!.status.error}');
}
```

### Typed canvas helpers

`TaskSignature<T>` (and the `task<T>()` helper) lets you declare the result type
for canvas primitives. The existing `Canvas.group`, `Canvas.chain`, and
`Canvas.chord` APIs now accept generics so typed values flow through sequential
steps, groups, and chords without manual casts:

```dart
final dispatch = await canvas.group<OrderSummary>([
  task<OrderSummary>(
    'orders.fetch',
    args: {'storeId': 42},
    decode: (payload) => OrderSummary.fromJson(
      payload! as Map<String, Object?>,
    ),
  ),
  task<OrderSummary>('orders.refresh'),
]);

dispatch.results.listen((result) {
  if (result.isSucceeded) {
    dashboard.update(result.value!);
  }
});

final chainResult = await canvas.chain<int>([
  task<int>('metrics.seed', args: {'value': 1}),
  task<int>('metrics.bump', args: {'add': 3}),
]);
print(chainResult.value); // 4

final chordResult = await canvas.chord<double>(
  body: [
    task<double>('image.resize', args: {'size': 256}),
    task<double>('image.resize', args: {'size': 512}),
  ],
  callback: task('image.aggregate'),
);
print('Body results: ${chordResult.values}');
```

### Task payload encoders

By default Stem stores handler arguments/results exactly as provided (JSON-friendly
structures). Configure default `TaskPayloadEncoder`s when bootstrapping `StemApp`,
`StemWorkflowApp`, or `Canvas` to plug in custom serialization (encryption,
compression, base64 wrappers, etc.) for both task arguments and persisted results:

```dart
import 'dart:convert';

class Base64ResultEncoder extends TaskPayloadEncoder {
  const Base64ResultEncoder();

  @override
  Object? encode(Object? value) {
    if (value is String) {
      return base64Encode(utf8.encode(value));
    }
    return value;
  }

  @override
  Object? decode(Object? stored) {
    if (stored is String) {
      return utf8.decode(base64Decode(stored));
    }
    return stored;
  }
}

final app = await StemApp.inMemory(
  tasks: [...],
  resultEncoder: const Base64ResultEncoder(),
  argsEncoder: const Base64ResultEncoder(),
  additionalEncoders: const [MyOtherEncoder()],
);

final canvas = Canvas(
  broker: broker,
  backend: backend,
  registry: registry,
  resultEncoder: const Base64ResultEncoder(),
  argsEncoder: const Base64ResultEncoder(),
);
```

Every envelope published by Stem carries the argument encoder id in headers/meta
(`stem-args-encoder` / `__stemArgsEncoder`) and every status stored in a result
backend carries the result encoder id (`__stemResultEncoder`). Workers use the same
`TaskPayloadEncoderRegistry` to resolve IDs, ensuring payloads are decoded exactly
once regardless of how many custom encoders you register.

Per-task overrides live on `TaskMetadata`, so both handlers and the corresponding
`TaskDefinition` share the same configuration:

```dart
class SecretTask extends TaskHandler<void> {
  static const _encoder = Base64ResultEncoder();

  @override
  TaskMetadata get metadata => const TaskMetadata(
        description: 'Encrypt args + results',
        argsEncoder: _encoder,
        resultEncoder: _encoder,
      );

  // ...
}
```

Encoders run exactly once per persistence/read cycle and fall back to the JSON
behavior when none is provided.

### Unique task deduplication

Set `TaskOptions(unique: true)` to prevent duplicate enqueues when a matching
task is already in-flight. Stem uses a `UniqueTaskCoordinator` backed by a
`LockStore` (Redis or in-memory) to claim uniqueness before publishing:

```dart
final lockStore = await RedisLockStore.connect('redis://localhost:6379');
final unique = UniqueTaskCoordinator(
  lockStore: lockStore,
  defaultTtl: const Duration(minutes: 5),
);

final stem = Stem(
  broker: broker,
  registry: registry,
  backend: backend,
  uniqueTaskCoordinator: unique,
);
```

The unique key is derived from:

- task name
- queue name
- task arguments
- headers
- metadata (excluding keys prefixed with `stem.`)

Keys are canonicalized (sorted maps, stable JSON) so equivalent inputs produce
the same hash. Use `uniqueFor` to control the TTL; when unset, the coordinator
falls back to `visibilityTimeout` or its default TTL.

Override the unique key when needed:

```dart
final id = await stem.enqueue(
  'orders.sync',
  args: {'id': 42},
  options: const TaskOptions(unique: true, uniqueFor: Duration(minutes: 10)),
  meta: {UniqueTaskMetadata.override: 'order-42'},
);
```

When a duplicate is skipped, Stem returns the existing task id, emits the
`stem.tasks.deduplicated` metric, and appends a duplicate entry to the result
backend metadata under `stem.unique.duplicates`.

### Durable workflow semantics

- Chords dispatch from workers. Once every branch completes, any worker may enqueue the callback, ensuring producer crashes do not block completion.
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
- Run execution is lease-based. The runtime claims each run with a lease
  (`runLeaseDuration`) and renews it while work continues. If another worker
  owns the lease, the task is retried so a takeover can occur once the lease
  expires. Keep `runLeaseDuration` at least as long as the broker visibility
  timeout and ensure `leaseExtension` renewals happen before either expires.
- Sleeps persist wake timestamps. When a resumed step calls `sleep` again, the
  runtime skips re-suspending once the stored `resumeAt` is reached so loop
  handlers can simply call `sleep` without extra guards.
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
- **Specs & tooling** - OpenSpec change workflow, quality gates (see `example/quality_gates`), chaos/regression suites.

## Documentation & Examples

- Full docs: [Full docs](.site/docs) (run `npm install && npm start` inside `.site/`).
- Guided onboarding: [Guided onboarding](.site/docs/getting-started/) (install → infra → ops → production).
- Examples (each has its own README):
- [workflows](example/workflows/) - end-to-end workflow samples (in-memory, sleep/event, SQLite, Redis). See `versioned_rewind.dart` for auto-versioned step rewinds.
- [cancellation_policy](example/workflows/cancellation_policy.dart) - demonstrates auto-cancelling long workflows using `WorkflowCancellationPolicy`.
- [rate_limit_delay](example/rate_limit_delay) - delayed enqueue, priority clamping, Redis rate limiter.
- [dlq_sandbox](example/dlq_sandbox) - dead-letter inspection and replay via CLI.
- [autoscaling_demo](example/autoscaling_demo) - autoscaling worker concurrency under queue backlog.
- [scheduler_observability](example/scheduler_observability) - Beat drift metrics, schedule signals, and CLI checks.
- [microservice](example/microservice), [monolith_service](example/monolith_service), [mixed_cluster](example/mixed_cluster) - production-style topologies.
- [progress_heartbeat](example/progress_heartbeat) - task progress + heartbeat reporting.
- [task_context_mixed](example/task_context_mixed) - TaskContext + TaskInvocationContext enqueue patterns, plus Celery-style apply_async options.
- [task_usage_patterns.dart](example/task_usage_patterns.dart) - in-memory TaskContext enqueue, TaskInvocationContext builder, and typed enqueue calls.
- [worker_control_lab](example/worker_control_lab) - worker ping/stats/revoke/shutdown drills.
- [unique_tasks](example/unique_tasks/unique_task_example.dart) - enables `TaskOptions.unique` with a shared lock store.
- [signing_key_rotation](example/signing_key_rotation) - rotate HMAC signing keys with overlap.
- [ops_health_suite](example/ops_health_suite) - CLI health checks + queue/worker snapshots.
- [quality_gates](example/quality_gates) - justfile-driven quality gate runner.
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

- `FakeWorkflowClock` keeps workflow tests deterministic. Inject the same clock
  into your runtime and store, then advance it directly instead of sleeping:

  ```dart
  final clock = FakeWorkflowClock(DateTime.utc(2024, 1, 1));
  final store = InMemoryWorkflowStore(clock: clock);
  final runtime = WorkflowRuntime(
    stem: stem,
    store: store,
    eventBus: InMemoryEventBus(store),
    clock: clock,
  );

  clock.advance(const Duration(seconds: 5));
  final dueRuns = await store.dueRuns(clock.now());
  ```
