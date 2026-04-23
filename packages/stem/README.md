<p align="center">
  <img src="../../.site/static/img/stem-logo.png" width="300" alt="Stem Logo" />
</p>

[![pub package](https://img.shields.io/pub/v/stem.svg)](https://pub.dev/packages/stem)
[![Dart](https://img.shields.io/badge/dart-%3E%3D3.9.2-blue.svg)](https://dart.dev/)
[![License](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow.svg)](https://www.buymeacoffee.com/kingwill101)

# Stem

Stem is a Dart-first background job and workflow platform: enqueue work, run workers, and orchestrate durable workflows.

For full docs, API references, and in-depth guides, visit
https://kingwill101.github.io/stem.

## Packages

| Package | Description | pub.dev |
|---------|-------------|---------|
| [`stem`](https://github.com/kingwill101/stem/tree/master/packages/stem) | Core runtime: contracts, worker, scheduler, in-memory adapters, signals, Canvas, workflows | [![pub](https://img.shields.io/pub/v/stem.svg)](https://pub.dev/packages/stem) |
| [`stem_cli`](https://github.com/kingwill101/stem/tree/master/packages/stem_cli) | Command-line tooling (`stem` executable) and CLI utilities | [![pub](https://img.shields.io/pub/v/stem_cli.svg)](https://pub.dev/packages/stem_cli) |
| [`stem_memory`](https://github.com/kingwill101/stem/tree/master/packages/stem_memory) | In-memory adapter package (broker/backend/workflow/scheduler factories) | [![pub](https://img.shields.io/pub/v/stem_memory.svg)](https://pub.dev/packages/stem_memory) |
| [`stem_sqlite`](https://github.com/kingwill101/stem/tree/master/packages/stem_sqlite) | SQLite broker and result backend for local dev/testing | [![pub](https://img.shields.io/pub/v/stem_sqlite.svg)](https://pub.dev/packages/stem_sqlite) |
| [`stem_redis`](https://github.com/kingwill101/stem/tree/master/packages/stem_redis) | Redis Streams broker, result backend, and watchdog helpers | [![pub](https://img.shields.io/pub/v/stem_redis.svg)](https://pub.dev/packages/stem_redis) |
| [`stem_postgres`](https://github.com/kingwill101/stem/tree/master/packages/stem_postgres) | Postgres broker, result backend, and scheduler stores | [![pub](https://img.shields.io/pub/v/stem_postgres.svg)](https://pub.dev/packages/stem_postgres) |
| [`stem_flutter`](https://github.com/kingwill101/stem/tree/master/packages/stem_flutter) | Adapter-neutral Flutter helpers for mobile worker isolates and queue monitoring | [![pub](https://img.shields.io/pub/v/stem_flutter.svg)](https://pub.dev/packages/stem_flutter) |
| [`stem_flutter_sqlite`](https://github.com/kingwill101/stem/tree/master/packages/stem_flutter_sqlite) | Flutter SQLite runtime/storage helpers for mobile Stem apps | [![pub](https://img.shields.io/pub/v/stem_flutter_sqlite.svg)](https://pub.dev/packages/stem_flutter_sqlite) |
| [`stem_builder`](https://github.com/kingwill101/stem/tree/master/packages/stem_builder) | Build-time code generator for annotated tasks and workflows | [![pub](https://img.shields.io/pub/v/stem_builder.svg)](https://pub.dev/packages/stem_builder) |
| [`stem_adapter_tests`](https://github.com/kingwill101/stem/tree/master/packages/stem_adapter_tests) | Shared contract test suites for adapter implementations | [![pub](https://img.shields.io/pub/v/stem_adapter_tests.svg)](https://pub.dev/packages/stem_adapter_tests) |
| [`stem_dashboard`](https://github.com/kingwill101/stem/tree/master/packages/dashboard) | Hotwire-based operations dashboard (experimental) | — |

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

## Install

```bash
dart pub add stem
# Optional adapters
dart pub add stem_redis     # Redis broker/backend
dart pub add stem_postgres  # Postgres broker/backend
dart pub add stem_sqlite    # SQLite broker/backend
dart pub add -d stem_builder # for annotations/codegen (optional)
dart pub add -d stem_cli      # for CLI tooling
```


## Examples

`StemApp` and `StemWorkflowApp` shortcut helpers lazily start their managed
worker by default. Pass `allowWorkerAutoStart: false` when you want producer
or orchestration shortcuts without starting that worker in the background,
then call `start()` explicitly when you're ready. `StemWorkflowApp` also
exposes `startRuntime()` and `startWorker()` when you want those lifecycles
split.

### Minimal in-memory task + worker

```dart
import "dart:async";
import "package:stem/stem.dart";

class HelloTask extends TaskHandler<void> {
  @override
  String get name => "demo.hello";

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    final name = args.valueOr<String>("name", "world");
    print("Hello $name");
  }
}

Future<void> main() async {
  final client = await StemClient.inMemory(tasks: [HelloTask()]);
  final worker = await client.createWorker();
  unawaited(worker.start());

  await client.enqueueValue("demo.hello", const {"name": "Stem"});
  await Future<void>.delayed(const Duration(seconds: 1));

  await worker.shutdown();
  await client.close();
}
```

### Reusable stack from URL (Redis)

```dart
import "package:stem/stem.dart";
import "package:stem_redis/stem_redis.dart";

Future<void> main() async {
  final client = await StemClient.fromUrl(
    "redis://localhost:6379",
    adapters: const [StemRedisAdapter()],
    overrides: const StemStoreOverrides(
      backend: "redis://localhost:6379/1",
    ),
    tasks: [HelloTask()],
  );

  final worker = await client.createWorker();
  unawaited(worker.start());

  await client.enqueueValue("demo.hello", const {"name": "Redis"});
  await Future<void>.delayed(const Duration(seconds: 1));

  await worker.shutdown();
  await client.close();
}
```

### Typed task definition and waiting for result

```dart
class HelloArgs {
  const HelloArgs({required this.name});
  final String name;

  Map<String, dynamic> toJson() => {"name": name};
  factory HelloArgs.fromJson(Map<String, dynamic> json) =>
      HelloArgs(name: json["name"] as String);
}

class HelloTask2 extends TaskHandler<String> {
  static final definition = TaskDefinition<HelloArgs, String>.json(
    name: "demo.hello2",
    metadata: const TaskMetadata(description: "typed hello task"),
  );

  @override
  String get name => definition.name;

  @override
  Future<String> call(TaskContext context, Map<String, Object?> args) async {
    final payload = HelloArgs.fromJson(args.cast<String, dynamic>());
    return "Hello ${payload.name}";
  }
}

Future<void> main() async {
  final client = await StemClient.inMemory(tasks: [HelloTask2()]);
  final worker = await client.createWorker();
  unawaited(worker.start());

  final result = await HelloTask2.definition.enqueueAndWait(
    client,
    const HelloArgs(name: "Typed"),
  );
  print(result?.value);

  await worker.shutdown();
  await client.close();
}
```

### Workflow quick-start (Flow)

```dart
import "package:stem/stem.dart";

final onboardingFlow = Flow<String>(
  name: "demo.onboarding",
  build: (flow) {
    flow.step("welcome", (ctx) async {
      return "Welcome ${ctx.requiredParam<String>("name")}";
    });
    flow.step("done", (ctx) async => "Done");
  },
);

Future<void> main() async {
  final appClient = await StemClient.inMemory();
  final app = await appClient.createWorkflowApp(
    flows: [onboardingFlow],
    allowWorkerAutoStart: false,
  );
  await app.start();

  final ref = onboardingFlow.refJson(HelloArgs.fromJson);
  final runId = await ref.start(app, params: const HelloArgs(name: "Stem"));
  final result = await ref.waitFor(app, runId);

  print(result?.value);
  await app.shutdown();
  await appClient.close();
}
```

### Annotated workflow + task with `stem_builder`

```dart
import "package:stem/stem.dart";
import "package:stem_builder/stem_builder.dart";

part "definitions.stem.g.dart";

@WorkflowDefn(name: "builder.signup", kind: WorkflowKind.script)
class BuilderSignupWorkflow {
  Future<String> run(String email) async {
    final userId = await createUser(email);
    await finalizeSignup(userId: userId);
    return userId;
  }

  @WorkflowStep(name: "create-user")
  Future<String> createUser(String email) async {
    return "user-$email";
  }

  @WorkflowStep(name: "finalize")
  Future<void> finalizeSignup({required String userId}) async {}
}

@TaskDefn(name: "builder.send_welcome")
Future<void> sendWelcomeEmail(
  String email, {
  TaskExecutionContext? context,
}) async {
  // optional: use context for logger/meta/retry helpers
}
```

```bash
dart run build_runner build

# After generation, use module + generated defs
```

```dart
// example usage after codegen
final client = await StemClient.inMemory(module: stemModule);
final app = await client.createWorkflowApp(allowWorkerAutoStart: false);
await app.start();

final runId = await StemWorkflowDefinitions.builderSignup.startAndWait(
  app,
  "alice@example.com",
);
final result = await StemWorkflowDefinitions.builderSignup.waitFor(app, runId);
print(result?.value); // {user: alice@example.com}
```

### Workflow with multiple worker queues

```dart
import "package:stem/stem.dart";

final onboardingFlow = Flow<Map<String, String>>(
  name: "workflow.multi_workers",
  build: (flow) {
    flow.step("dispatch", (ctx) async {
      final notifyTaskId = await ctx.enqueue(
        "notify.send",
        args: {"email": "alex@example.com"},
        enqueueOptions: const TaskEnqueueOptions(queue: "notifications"),
      );
      final analyticsTaskId = await ctx.enqueue(
        "analytics.track",
        args: {"userId": "alex", "event": "account.created"},
        enqueueOptions: const TaskEnqueueOptions(queue: "analytics"),
      );
      return {"notifyTaskId": notifyTaskId, "trackTaskId": analyticsTaskId};
    });
  },
);

class NotifyTask extends TaskHandler<String> {
  @override
  String get name => "notify.send";

  @override
  TaskOptions get options => const TaskOptions(queue: "notifications");

  @override
  Future<String> call(TaskContext context, Map<String, Object?> args) async =>
      "notified:${args['email']}";
}

class AnalyticsTask extends TaskHandler<String> {
  @override
  String get name => "analytics.track";

  @override
  TaskOptions get options => const TaskOptions(queue: "analytics");

  @override
  Future<String> call(TaskContext context, Map<String, Object?> args) async =>
      "tracked:${args['event']}";
}

Future<void> main() async {
  final client = await StemClient.inMemory();
  final app = await client.createWorkflowApp(
    flows: [onboardingFlow],
    workerConfig: const StemWorkerConfig(queue: "workflow"),
  );
  await app.start();

  final notifications = await client.createWorker(
    workerConfig: StemWorkerConfig(
      queue: "notifications-worker",
      consumerName: "notifications-worker",
      subscription: RoutingSubscription.singleQueue("notifications"),
    ),
    tasks: [NotifyTask()],
  );
  final analytics = await client.createWorker(
    workerConfig: StemWorkerConfig(
      queue: "analytics-worker",
      consumerName: "analytics-worker",
      subscription: RoutingSubscription.singleQueue("analytics"),
    ),
    tasks: [AnalyticsTask()],
  );

  await notifications.start();
  await analytics.start();

  final result = await onboardingFlow.startAndWait(app);
  final taskIds = result?.value ?? const <String, String>{};
  print(await app.waitForTask<String>(taskIds['notifyTaskId']!));
  print(await app.waitForTask<String>(taskIds['trackTaskId']!));

  await notifications.shutdown();
  await analytics.shutdown();
  await app.close();
  await client.close();
}
```

### 5) CLI at a glance

```bash
# Start a worker or run built-in introspection commands
stem --help
stem worker start --help
stem wf --help
```


### General worker management (multi-worker setup)

```dart
import "package:stem/stem.dart";

class EmailTask extends TaskHandler<void> {
  @override
  String get name => "notify.send";

  @override
  TaskOptions get options => const TaskOptions(queue: "notify");

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    print("notify queue: ${args['to']}");
  }
}

class ReportTask extends TaskHandler<void> {
  @override
  String get name => "reports.aggregate";

  @override
  TaskOptions get options => const TaskOptions(queue: "reports");

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    print("reports queue: ${args['reportId']}");
  }
}

Future<void> main() async {
  final client = await StemClient.inMemory();

  final notifyWorker = await client.createWorker(
    workerConfig: StemWorkerConfig(
      queue: "notify-worker",
      consumerName: "notify-worker",
      subscription: RoutingSubscription.singleQueue("notify"),
    ),
    tasks: [EmailTask()],
  );

  final reportsWorker = await client.createWorker(
    workerConfig: StemWorkerConfig(
      queue: "reports-worker",
      consumerName: "reports-worker",
      subscription: RoutingSubscription.singleQueue("reports"),
    ),
    tasks: [ReportTask()],
  );

  await notifyWorker.start();
  await reportsWorker.start();

  await client.enqueue(
    "notify.send",
    args: {"to": "ops@example.com"},
  );
  await client.enqueue(
    "reports.aggregate",
    args: {"reportId": "r-2026-q1"},
  );

  await Future<void>.delayed(const Duration(milliseconds: 400));

  await notifyWorker.shutdown();
  await reportsWorker.shutdown();
  await client.close();
}
```

- Full example that combines a workflow dispatching to dedicated workers:
  [multiple_workers.dart](example/workflows/multiple_workers.dart)

## Want depth?

This README is intentionally example-focused.
For implementation details, runtime semantics, adapter tuning, and operational playbooks,
see the full docs at https://kingwill101.github.io/stem.


## Documentation & Examples


- Guided onboarding: [Guided onboarding](.site/docs/getting-started/) (install → infra → ops → production).
- Examples (each has its own README):
- [workflows](example/workflows/) - end-to-end workflow samples (in-memory, sleep/event, SQLite, Redis). See `versioned_rewind.dart` for auto-versioned step rewinds.
- [multiple_workers.dart](example/workflows/multiple_workers.dart) - workflow dispatching tasks to `notifications` and `analytics` workers.
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
