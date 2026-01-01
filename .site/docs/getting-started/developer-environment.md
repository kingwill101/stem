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
share them across your app:

```dart title="lib/stem_bootstrap.dart"
import 'dart:io';

import 'package:stem/stem.dart';

Future<Bootstrap> bootstrapStem(SimpleTaskRegistry registry) async {
  final config = StemConfig.fromEnvironment(Platform.environment);

  final broker = await RedisStreamsBroker.connect(config.brokerUrl);
  final backend = await RedisResultBackend.connect(config.resultBackendUrl);
  final rateLimiter = await RedisRateLimiter.connect(config.rateLimiterUrl);
  final revokeStore = await RedisRevokeStore.connect(config.revokeStoreUrl);

  final stem = Stem(
    broker: broker,
    backend: backend,
    registry: registry,
    routing: RoutingRegistry(config.routing),
  );

  final worker = Worker(
    broker: broker,
    backend: backend,
    registry: registry,
    revokeStore: revokeStore,
    rateLimiter: rateLimiter,
    queue: 'default',
    concurrency: 8,
    autoscaler: Autoscaler(
      minimum: 2,
      maximum: 16,
      scaleUpLagThreshold: const Duration(seconds: 10),
    ),
  );

  return Bootstrap(
    stem: stem,
    worker: worker,
    config: config,
    rateLimiter: rateLimiter,
  );
}

class Bootstrap {
  Bootstrap({
    required this.stem,
    required this.worker,
    required this.config,
    required this.rateLimiter,
  });

  final Stem stem;
  final Worker worker;
  final StemConfig config;
  final RateLimiter rateLimiter;
}
```

This single bootstrap gives you access to routing, rate limiting, revoke
storage, and queue configuration—all backed by Redis.

## 3. Launch Workers, Beat, and Producers

With the environment configured, run Stem components from separate terminals:

```bash
# Terminal 1 — worker with multi-queue subscription and autoscaling.
stem worker start \
  --registry lib/main.dart \
  --broker "$STEM_BROKER_URL" \
  --queues default,reports,emails \
  --autoscale 2:16

# Terminal 2 — Beat scheduler reading JSON specs from disk.
stem schedule apply config/schedules.json --store "$STEM_SCHEDULE_STORE_URL"
stem schedule list --store "$STEM_SCHEDULE_STORE_URL"
stem beat start --store "$STEM_SCHEDULE_STORE_URL"

# Terminal 3 — enqueue tasks with priority overrides and broadcast routes.
stem enqueue reports.generate \
  --args '{"customerId":42}' \
  --not-before 5m \
  --priority 8 \
  --registry lib/main.dart

stem enqueue broadcast://maintenance \
  --args '{"action":"restart"}' \
  --routing-config config/routing.yaml \
  --registry lib/main.dart
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

```dart
final canvas = Canvas(
  broker: bootstrap.stem.broker,
  backend: await RedisResultBackend.connect(
    bootstrap.config.resultBackendUrl,
  ),
  registry: registry,
);

final ids = await canvas.group([
  task('media.resize', args: {'file': 'hero.png'}),
  task('media.resize', args: {'file': 'thumb.png'}),
], groupId: 'image-assets');

final chordId = await canvas.chord(
  body: [
    task('reports.render', args: {'week': '2024-W28'}),
    task('reports.render', args: {'week': '2024-W29'}),
  ],
  callback: task(
    'billing.email-receipt',
    args: {'to': 'finance@example.com'},
    options: const TaskOptions(queue: 'emails'),
  ),
);

print('Group dispatched: $ids');
print('Chord callback task id: $chordId');
```

Later, you can monitor status from any machine:

```dart
final backend = await RedisResultBackend.connect(
  Platform.environment['STEM_RESULT_BACKEND_URL']!,
);
final status = await backend.get(chordId);
print('Chord completion state: ${status?.state}');
```

## 5. Listen to Signals for Cross-Cutting Integrations

Signals surface lifecycle milestones that you can pipe into analytics or
incident tooling:

```dart title="lib/signals.dart"
import 'package:stem/stem.dart';

void installSignalHandlers() {
  StemSignals.taskSucceeded.connect((payload) {
    if (payload.sender == 'reports.render') {
      print('Report ${payload.envelope.id} succeeded in '
          '${payload.duration.inMilliseconds}ms');
    }
  });

  StemSignals.workerReady.connect((payload) {
    print('Worker ${payload.workerId} ready on ${payload.hostname}');
  });
}
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
