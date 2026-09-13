---
name: stem-tasks
description: >-
  Use when defining, registering, enqueueing, running, or observing Stem tasks
  and workers. Prefer the stable public API and verify task names, codecs,
  retries, and lifecycle against the installed package version.
---

# Stem tasks

## Rules

- Prefer `package:stem/stable.dart` for application code. Use
  `package:stem/advanced.dart` only when the task requires a lower-level
  transport, signal, or instrumentation API.
- A task has a stable string name and a registered `TaskHandler`; register the
  handler before enqueueing its name.
- Keep task arguments and results within the configured payload contract.
  Use `enqueueValue` with an explicit `Codec<T, Object?>` for a typed value
  that is not covered by the configured codec registry.
- Prefer a generated typed task definition when `stem_builder` is in use. For
  hand-written code, construct a `TaskDefinition` explicitly and enqueue its
  `buildCall`; do not assume that a registry will infer a codec for an
  unregistered Dart type.
- Treat delivery as at-least-once. Retries and lease recovery can run a
  handler again, so make external side effects idempotent and use an
  application idempotency key where needed. Stem does not promise exactly-once
  side effects.
- `StemApp.create` and `StemFlutter.createApp` configure resources but do not
  start consumption. Call `app.start()` once the process is ready, and call
  `app.shutdown()` during orderly teardown.
- `waitForTask` observes a result; it is not a guarantee that a side effect
  happened exactly once. Give it a timeout when the caller must remain bounded.
- Do not claim that a Dart or Flutter worker is an OS-managed background
  scheduler. Mobile background execution needs platform scheduling and policy
  outside Stem.

## Example: in-memory task

```dart
import 'dart:async';

import 'package:stem/stable.dart';

Future<void> main() async {
  final definition = TaskDefinition<Map<String, int>, int>(
    name: 'math.add',
    encodeArgs: (value) => value,
    decodeArgs: (value) => Map<String, int>.from(value as Map),
  );
  final handler = definition.handler(
    entrypoint: (context, args) async => args['a']! + args['b']!,
  );
  final client = await StemClient.inMemory(tasks: [handler]);
  final worker = await client.createWorker();
  unawaited(worker.start());
  try {
    final call = definition.buildCall({'a': 2, 'b': 3});
    final id = await client.enqueueCall(call);
    final result = await client.waitForTask<int>(id);
    print(result?.value); // 5
  } finally {
    await worker.shutdown();
    await client.close();
  }
}
```

Use the app's `enqueue`, `enqueueValue`, or `enqueueCall` methods when that
better matches the application's registration boundary. Keep task names stable
when persisted messages may outlive a deployment.

## Validation checklist

1. Confirm the handler is registered in the same app/worker that consumes it.
2. Confirm the codec's encoded value is accepted by the broker/backend.
3. Test retry and restart paths with an idempotent handler.
4. Await `shutdown`; do not terminate the process while deliveries or store
   cleanup are still in flight.
