---
title: Programmatic Workers & Enqueuers
sidebar_label: Programmatic Usage
sidebar_position: 2
slug: /workers/programmatic
---

Use Stem's Dart APIs to embed task production and processing inside your
application services. This guide focuses on the two core roles: **producer**
(enqueuer) and **worker**.

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Producer (Enqueuer)

<Tabs>
<TabItem value="minimal" label="Minimal">

```dart title="lib/producer.dart"
import 'package:stem/stem.dart';

Future<void> main() async {
  final registry = SimpleTaskRegistry();

  final stem = Stem(
    broker: InMemoryBroker(),
    registry: registry,
    backend: InMemoryResultBackend(),
  );

  final taskId = await stem.enqueue(
    'email.send',
    args: {'to': 'hello@example.com', 'subject': 'Welcome'},
  );

  print('Enqueued $taskId');
}
```

</TabItem>
<TabItem value="redis" label="Redis Broker">

```dart title="lib/producer_redis.dart"
import 'dart:io';
import 'package:stem/stem.dart';

Future<void> main() async {
  final brokerUrl =
      Platform.environment['STEM_BROKER_URL'] ?? 'redis://localhost:6379';
  final broker = await RedisStreamsBroker.connect(brokerUrl);

  final stem = Stem(
    broker: broker,
    registry: SimpleTaskRegistry(),
    backend: await RedisResultBackend.connect('$brokerUrl/1'),
  );

  await stem.enqueue(
    'report.generate',
    args: {'reportId': 'monthly-2025-10'},
    options: const TaskOptions(queue: 'reports'),
  );
}
```

</TabItem>
<TabItem value="signing" label="Payload Signing">

```dart title="lib/producer_signed.dart"
import 'dart:io';
import 'package:stem/stem.dart';

Future<void> main() async {
  final config = StemConfig.fromEnvironment();
  final signer = PayloadSigner.maybe(config.signing);

  final stem = Stem(
    broker: await RedisStreamsBroker.connect(config.brokerUrl, tls: config.tls),
    registry: SimpleTaskRegistry(),
    backend: InMemoryResultBackend(),
    signer: signer,
  );

  await stem.enqueue(
    'billing.charge',
    args: {'customerId': 'cust_123', 'amount': 42_00},
  );
}
```

</TabItem>
</Tabs>

### Tips

- Always reuse a `Stem` instance rather than creating one per request.
- Use `TaskOptions` to set queue, retries, timeouts, and isolation.
- Add custom metadata via the `meta` argument for observability or downstream
  processing.

## Worker

<Tabs>
<TabItem value="minimal" label="Minimal">

```dart title="bin/worker.dart"
import 'dart:async';
import 'package:stem/stem.dart';

class EmailTask implements TaskHandler<void> {
  @override
  String get name => 'email.send';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 2);

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    final to = args['to'] as String;
    print('Sending to $to (attempt ${context.attempt})');
  }
}

Future<void> main() async {
  final registry = SimpleTaskRegistry()..register(EmailTask());
  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    queue: 'default',
  );

  await worker.start();
}
```

</TabItem>
<TabItem value="redis" label="Redis Broker">

```dart title="bin/worker_redis.dart"
import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';

Future<void> main() async {
  final brokerUrl =
      Platform.environment['STEM_BROKER_URL'] ?? 'redis://localhost:6379';
  final registry = SimpleTaskRegistry()..register(EmailTask());

  final worker = Worker(
    broker: await RedisStreamsBroker.connect(brokerUrl),
    registry: registry,
    backend: await RedisResultBackend.connect('$brokerUrl/1'),
    queue: 'default',
    concurrency: Platform.numberOfProcessors,
  );

  await worker.start();
}

class EmailTask implements TaskHandler<void> {
  @override
  String get name => 'email.send';

  @override
  TaskOptions get options => const TaskOptions(
        queue: 'default',
        maxRetries: 3,
        visibilityTimeout: Duration(seconds: 30),
      );

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    // call your email provider here
  }
}
```

</TabItem>
<TabItem value="advanced" label="Retries & Signals">

```dart title="bin/worker_retry.dart"
import 'dart:async';
import 'package:stem/stem.dart';

class FlakyTask implements TaskHandler<void> {
  @override
  String get name => 'demo.flaky';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 2);

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    if (context.attempt < 2) {
      throw StateError('Simulated failure');
    }
    print('Succeeded on attempt ${context.attempt}');
  }
}

Future<void> main() async {
  StemSignals.onTaskRetry((payload, _) {
    print('[retry] next run at: ${payload.nextRetryAt}');
  });

  final registry = SimpleTaskRegistry()..register(FlakyTask());
  final worker = Worker(
    broker: InMemoryBroker(),
    registry: registry,
    backend: InMemoryResultBackend(),
    retryStrategy: ExponentialJitterRetryStrategy(
      base: const Duration(milliseconds: 200),
      max: const Duration(seconds: 1),
    ),
  );

  await worker.start();
}
```

</TabItem>
</Tabs>

### Lifecycle Tips

- Call `worker.shutdown()` on SIGINT/SIGTERM to drain in-flight tasks and emit
  `workerStopping`/`workerShutdown` signals.
- Monitor heartbeats via `StemSignals.workerHeartbeat` or the heartbeat backend
  for liveness checks.
- Use `WorkerLifecycleConfig` to install signal handlers, configure soft/hard
  shutdown timeouts, and recycle isolates after N tasks or memory thresholds.

## Putting It Together

A lightweight service wires the producer and worker into your application
startup:

```dart title="lib/bootstrap.dart"
import 'package:stem/stem.dart';

class StemRuntime {
  StemRuntime({required this.registry, required this.brokerUrl});

  final TaskRegistry registry;
  final String brokerUrl;

  late final Stem stem = Stem(
    broker: InMemoryBroker(),
    registry: registry,
    backend: InMemoryResultBackend(),
  );

  late final Worker worker = Worker(
    broker: InMemoryBroker(),
    registry: registry,
    backend: InMemoryResultBackend(),
  );

  Future<void> start() async {
    await worker.start();
  }

  Future<void> stop() async {
    await worker.shutdown();
  }
}
```

Swap the in-memory adapters for Redis/Postgres when you deploy, keeping the API
surface the same.

## Checklist

- Reuse producer and worker objects—avoid per-request construction.
- Inject the `TaskRegistry` from a central module so producers and workers stay
  in sync.
- Capture task IDs returned by `Stem.enqueue` when you need to poll results or
  correlate with your own auditing.
- Emit lifecycle signals (`StemSignals`) and wire logs/metrics early so
  production instrumentation is already in place.
- For HTTP/GraphQL handlers, wrap enqueues in try/catch to surface validation
  errors before tasks hit the queue.

Next, continue with the [Worker Control CLI](./worker-control.md) or explore
[Signals](../core-concepts/signals.md) for advanced instrumentation.
