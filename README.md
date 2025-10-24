[![pub package](https://img.shields.io/pub/v/stem.svg)](https://pub.dev/packages/stem)
[![Dart](https://img.shields.io/badge/dart-%3E%3D3.9.0-blue.svg)](https://dart.dev/)
[![License](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)
[![Build Status](https://github.com/kingwill101/stem/workflows/ci/badge.svg)](https://github.com/kingwill101/stem/actions)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow.svg)](https://www.buymeacoffee.com/kingwill101)

# Stem

 Stem is a Dart-native background job platform. It gives you Celery-style
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

- Full docs: [Full docs](.site/docs) (run `npm install && npm start` inside `.site/`).
- Guided onboarding: [Guided onboarding](.site/docs/getting-started/) (install → infra → ops → production).
- Examples (each has its own README):
  - [rate_limit_delay](example/rate_limit_delay) – delayed enqueue, priority clamping, Redis rate limiter.
  - [dlq_sandbox](example/dlq_sandbox) – dead-letter inspection and replay via CLI.
  - [microservice](example/microservice), [monolith_service](example/monolith_service), [mixed_cluster](example/mixed_cluster) – production-style topologies.
  - [security examples](example/security/*) – payload signing + TLS profiles.
  - [postgres_tls](example/postgres_tls) – Redis broker + Postgres backend secured via the shared `STEM_TLS_*` settings.
  - [otel_metrics](example/otel_metrics) – OTLP collectors + Grafana dashboards.
