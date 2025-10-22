---
title: Quick Start
sidebar_label: Quick Start
sidebar_position: 2
slug: /getting-started/quick-start
---

Spin up Stem in minutes with nothing but Dart installed. This walkthrough stays
fully in-memory so you can focus on the core pipeline: enqueueing, retries,
delays, priorities, and chaining work together.

## 1. Create a Demo Project

```bash
dart create stem_quickstart
cd stem_quickstart

# Add Stem as a dependency and activate the CLI.
dart pub add stem
dart pub global activate stem
```

Add the Dart pub cache to your `PATH` so the `stem` CLI is reachable:

```bash
export PATH="$HOME/.pub-cache/bin:$PATH"
stem --version
```

## 2. Register Tasks with Options

Replace the generated `bin/stem_quickstart.dart` with the following script. It
registers two tasks, each showing different Stem options—retries, time limits,
rate limits, priorities, and custom queues.

```dart title="bin/stem_quickstart.dart"
import 'dart:async';

import 'package:stem/stem.dart';

class ResizeImageTask implements TaskHandler<void> {
  @override
  String get name => 'media.resize';

  @override
  TaskOptions get options => const TaskOptions(
        maxRetries: 5,
        softTimeLimit: Duration(seconds: 10),
        hardTimeLimit: Duration(seconds: 20),
        priority: 7,
        rateLimit: '20/m', // 20 tasks per minute across the cluster.
        visibilityTimeout: Duration(seconds: 60),
      );

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    final file = args['file'] as String? ?? 'unknown.png';
    context.heartbeat();
    print('[media.resize] resizing $file (attempt ${context.attempt})');
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

class EmailReceiptTask implements TaskHandler<void> {
  @override
  String get name => 'billing.email-receipt';

  @override
  TaskOptions get options => const TaskOptions(
        queue: 'emails',
        maxRetries: 3,
        priority: 9,
      );

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    final to = args['to'] as String? ?? 'customer@example.com';
    print('[billing.email-receipt] sent to $to');
  }
}

Future<void> main() async {
  final registry = SimpleTaskRegistry()
    ..register(ResizeImageTask())
    ..register(EmailReceiptTask());

  // In-memory adapters make the quick start self-contained.
  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();

  final worker = Worker(
    broker: broker,
    backend: backend,
    registry: registry,
    queue: 'default',
    consumerName: 'quickstart-worker',
    concurrency: 4,
  );

  // Start processing in the background.
  unawaited(worker.start());

  final stem = Stem(
    broker: broker,
    backend: backend,
    registry: registry,
  );

  // Enqueue immediately.
  final resizeId = await stem.enqueue(
    'media.resize',
    args: {'file': 'report.png'},
  );

  // Enqueue with delay, priority override, and custom metadata.
  final emailId = await stem.enqueue(
    'billing.email-receipt',
    args: {'to': 'alice@example.com'},
    options: const TaskOptions(priority: 10),
    notBefore: DateTime.now().add(const Duration(seconds: 5)),
    meta: {'orderId': 4242},
  );

  print('Enqueued tasks: resize=$resizeId email=$emailId');

  // Inspect the recorded result once the worker finishes.
  await Future<void>.delayed(const Duration(seconds: 6));
  final resizeStatus = await backend.get(resizeId);
  print('Resize status: ${resizeStatus?.state} (${resizeStatus?.attempt})');

  await worker.shutdown();
}
```

Run the script:

```bash
dart run bin/stem_quickstart.dart
```

Stem handles retries, time limits, rate limiting, and priority ordering even
with the in-memory adapters—great for tests and local demos.

## 3. Compose Work with Canvas

Stem’s canvas API lets you chain, group, or create chords of tasks. Add this
helper to the bottom of the file above to try a chain:

```dart
Future<void> runCanvasExample(
  Canvas canvas,
) async {
  final chainId = await canvas.chain([
    task(
      'media.resize',
      args: {'file': 'canvas.png'},
      options: const TaskOptions(priority: 5),
    ),
    task(
      'billing.email-receipt',
      args: {'to': 'ops@example.com'},
      options: const TaskOptions(queue: 'emails'),
    ),
  ]);

  print('Canvas chain started. Final task id = $chainId');
}
```

Then call it from `main` once the worker has started:

```dart
  final canvas = Canvas(
    broker: broker,
    backend: backend,
    registry: registry,
  );
  await runCanvasExample(canvas);
```

Each step records progress in the result backend, and failures trigger retries
or DLQ placement according to `TaskOptions`.

## 4. Peek at Retries and DLQ

Force a failure to see retry behaviour:

```dart
class EmailReceiptTask implements TaskHandler<void> {
  @override
  String get name => 'billing.email-receipt';

  @override
  TaskOptions get options => const TaskOptions(
        queue: 'emails',
        maxRetries: 3,
        priority: 9,
      );

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    final to = args['to'] as String? ?? 'customer@example.com';
    if (context.attempt < 2) {
      throw StateError('Simulated failure for $to');
    }
    print('[billing.email-receipt] delivered on attempt ${context.attempt}');
  }
}
```

The retry pipeline and DLQ logic are built into the worker. When the task
exceeds `maxRetries`, the envelope moves to the DLQ; you’ll learn how to inspect
and replay those entries in the next guide.

## 5. Where to Next

- Connect Stem to Redis/Postgres, try broadcast routing, and run Beat in
  [Connect to Infrastructure](./developer-environment.md).
- Explore worker control commands, DLQ tooling, and OpenTelemetry export in
  [Observe & Operate](./observability-and-ops.md).
- Keep the script—you’ll reuse the registry and tasks in later steps.
