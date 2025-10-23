# Stem

Stem is a spec-driven background job platform for Dart. It gives you Celery-style
task execution with a Dart-first API, Redis Streams integration, retries,
scheduling, observability, and security tooling—all without leaving the Dart
ecosystem.

## Install

```bash
dart pub add stem
dart pub global activate stem
```

Add the pub-cache bin directory to your `PATH` so the `stem` CLI is available:

```bash
export PATH="$HOME/.pub-cache/bin:$PATH"
stem --help
```

## Quick Start

```dart
import 'dart:async';
import 'package:stem/stem.dart';

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

## Features

- **Task pipeline** – enqueue with delays, priorities, idempotency helpers, and retries.
- **Workers** – isolate pools with soft/hard time limits, autoscaling, and remote control (`stem worker ping|revoke|shutdown`).
- **Scheduling** – Beat-style scheduler with interval/cron/solar/clocked entries and drift tracking.
- **Observability** – OpenTelemetry metrics/traces, heartbeats, CLI inspection (`stem observe`, `stem dlq`).
- **Security** – Payload signing (HMAC or Ed25519), TLS automation scripts, revocation persistence.
- **Adapters** – Redis Streams broker + Redis/Postgres result backends and schedule stores; in-memory drivers for tests.
- **Specs & tooling** – OpenSpec change workflow, quality gates (`tool/quality/run_quality_checks.sh`), chaos/regression suites.

## Documentation & Examples

- Full docs: `.site/docs` (run `npm install && npm start` inside `.site/`).
- Guided onboarding: `.site/docs/getting-started/` (install → infra → ops → production).
- Examples (each has its own README):
  - `examples/rate_limit_delay` – delayed enqueue, priority clamping, Redis rate limiter.
  - `examples/dlq_sandbox` – dead-letter inspection and replay via CLI.
  - `examples/microservice`, `examples/monolith_service`, `examples/mixed_cluster` – production-style topologies.
  - `examples/security/*` – payload signing + TLS profiles.
  - `examples/otel_metrics` – OTLP collectors + Grafana dashboards.
