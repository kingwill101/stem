---
id: canvas-guide
title: Canvas Patterns
sidebar_label: Canvas Patterns
---

This guide walks through Stem's task composition primitives—chains, groups, and
chords—using in-memory brokers and backends. Each snippet references a runnable
file under `examples/canvas_patterns/` so you can experiment locally with
`dart run`.

## Chains

Chains execute tasks serially. Each step receives the previous result via
`context.meta['chainPrevResult']`.

```dart
// examples/canvas_patterns/chain_example.dart
import 'dart:async';

import 'package:stem/stem.dart';

Future<void> main() async {
  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();
  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<String>(
        name: 'fetch.user',
        entrypoint: (context, args) async => 'Ada',
      ),
    )
    ..register(
      FunctionTaskHandler<String>(
        name: 'enrich.user',
        entrypoint: (context, args) async {
          final prev = context.meta['chainPrevResult'] as String? ?? 'Friend';
          return '$prev Lovelace';
        },
      ),
    )
    ..register(
      FunctionTaskHandler<Object?>(
        name: 'send.email',
        entrypoint: (context, args) async {
          final fullName = context.meta['chainPrevResult'] as String? ?? 'Friend';
          print('Sending email to $fullName');
          return null;
        },
      ),
    );

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    consumerName: 'chain-worker',
    concurrency: 1,
    prefetchMultiplier: 1,
  );
  await worker.start();

  final canvas = Canvas(broker: broker, backend: backend, registry: registry);
  final chainId = await canvas.chain([
    task('fetch.user'),
    task('enrich.user'),
    task('send.email'),
  ]);

  await _waitFor(() async {
    final status = await backend.get(chainId);
    return status?.state == TaskState.succeeded;
  });

  final status = await backend.get(chainId);
  print('Chain completed with state: ${status?.state}');

  await worker.shutdown();
  broker.dispose();
}

Future<void> _waitFor(
  Future<bool> Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
  Duration pollInterval = const Duration(milliseconds: 50),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await predicate()) return;
    await Future<void>.delayed(pollInterval);
  }
  throw TimeoutException('Timed out waiting for chain completion', timeout);
}
```

If any step fails, the chain stops immediately. Retry by invoking `canvas.chain`
again with the same signatures.

## Groups

Groups fan out work and persist each branch in the result backend.

```dart
// examples/canvas_patterns/group_example.dart
import 'dart:async';

import 'package:stem/stem.dart';

Future<void> main() async {
  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();
  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<int>(
        name: 'square',
        entrypoint: (context, args) async {
          final value = args['value'] as int;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return value * value;
        },
      ),
    );

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    consumerName: 'group-worker',
    concurrency: 2,
    prefetchMultiplier: 1,
  );
  await worker.start();

  final canvas = Canvas(broker: broker, backend: backend, registry: registry);
  const groupHandle = 'squares-demo';
  await canvas.group([
    task('square', args: <String, Object?>{'value': 2}),
    task('square', args: <String, Object?>{'value': 3}),
    task('square', args: <String, Object?>{'value': 4}),
  ], groupId: groupHandle);

  await _waitFor(() async {
    final status = await backend.getGroup(groupHandle);
    return status?.results.length == 3;
  });

  final groupStatus = await backend.getGroup(groupHandle);
  final values = groupStatus?.results.values.map((s) => s.payload).toList();
  print('Group results: $values');

  await worker.shutdown();
  broker.dispose();
}

Future<void> _waitFor(
  Future<bool> Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
  Duration pollInterval = const Duration(milliseconds: 50),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await predicate()) return;
    await Future<void>.delayed(pollInterval);
  }
  throw TimeoutException('Timed out waiting for group completion', timeout);
}
```

## Chords

Chords combine a group with a callback. Once all body tasks succeed, the callback
runs with `context.meta['chordResults']` populated.

```dart
// examples/canvas_patterns/chord_example.dart
import 'dart:async';

import 'package:stem/stem.dart';

Future<void> main() async {
  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();
  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<int>(
        name: 'fetch.metric',
        entrypoint: (context, args) async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          return args['value'] as int;
        },
      ),
    )
    ..register(
      FunctionTaskHandler<Object?>(
        name: 'aggregate.metric',
        entrypoint: (context, args) async {
          final values = (context.meta['chordResults'] as List?)
                  ?.whereType<int>()
                  .toList() ??
              const [];
          final sum = values.fold<int>(0, (a, b) => a + b);
          print('Aggregated result: $sum');
          return null;
        },
      ),
    );

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    consumerName: 'chord-worker',
    concurrency: 3,
    prefetchMultiplier: 1,
  );
  await worker.start();

  final canvas = Canvas(broker: broker, backend: backend, registry: registry);
  final callbackId = await canvas.chord(
    body: [
      task('fetch.metric', args: <String, Object?>{'value': 5}),
      task('fetch.metric', args: <String, Object?>{'value': 7}),
      task('fetch.metric', args: <String, Object?>{'value': 11}),
    ],
    callback: task('aggregate.metric'),
  );

  await _waitFor(() async {
    final status = await backend.get(callbackId);
    return status?.state == TaskState.succeeded;
  });

  final callbackStatus = await backend.get(callbackId);
  print('Callback state: ${callbackStatus?.state}');

  await worker.shutdown();
  broker.dispose();
}

Future<void> _waitFor(
  Future<bool> Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
  Duration pollInterval = const Duration(milliseconds: 50),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await predicate()) return;
    await Future<void>.delayed(pollInterval);
  }
  throw TimeoutException('Timed out waiting for chord completion', timeout);
}
```

If any branch fails, the callback is skipped and the chord group is marked as
failed. Inspect `backend.getGroup(chordId)` to see which branch failed before
retrying.

## Running the examples

From the repository root:

```bash
dart run examples/canvas_patterns/chain_example.dart
dart run examples/canvas_patterns/group_example.dart
dart run examples/canvas_patterns/chord_example.dart
```

Each script starts its own in-memory broker, backend, and worker.

## Best practices

- Keep callbacks idempotent; chords can be retried manually.
- Polling is fine for examples—production deployments should rely on
  notifications or shorter intervals.
- Expire group records via backend TTLs to avoid unbounded storage.
