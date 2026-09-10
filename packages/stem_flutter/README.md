# stem_flutter

Use **the same Stem application and task APIs in Flutter**. This package adds
Flutter initialization and conservative local-worker defaults—not another task
runtime, worker protocol, or monitoring API.

`StemFlutter.createApp()` returns an actual `StemApp`. Modules, task definitions,
typed arguments/results, registration, Canvas, middleware, routing, and worker
execution all remain core Stem features.

For durable local storage, use `stem_flutter_sqlite`.

## Getting started

```dart
import 'package:stem_flutter/stem_flutter.dart';

final doubleTask = TaskDefinition<int, int>(
  name: 'double',
  encodeArgs: (value) => {'value': value},
  decodeArgs: (args) => args['value']! as int,
);

Future<void> example() async {
  final app = await StemFlutter.createApp(
    module: StemModule(
      tasks: [
        doubleTask.handler(
          entrypoint: (context, value) async => value * 2,
        ),
      ],
    ),
  );

  try {
    await app.start(); // Explicit consumption, exactly like StemApp.
    final id = await doubleTask.enqueue(app, 21);
    final result = await doubleTask.waitFor(app, id);
    print(result?.value); // 42
  } finally {
    await app.shutdown();
  }
}
```

The package re-exports `package:stem/stable.dart`. Existing imports from `stem`
continue to work; the returned app is not a wrapper or a different implementation.

Without storage factories, this generic bootstrap uses Stem's in-memory stores.
Pass ordinary `StemBrokerFactory` and `StemBackendFactory` values for other
adapters. Ownership follows their configured disposal hooks.

If you already have core bootstrap wiring, keep it. Use Flutter's
`WidgetsFlutterBinding.ensureInitialized()` before opening stores that need
platform plugins. There is no need to replace existing `StemApp`, `StemClient`,
or `StemWorkflowApp` code.

## Execution and ownership

- Own the app above individual screens. A screen disappearing should not destroy
  the application's queue.
- Creating an app does **not** start its worker. Call `app.start()` when this
  process should consume work.
- `app.shutdown()` is final, idempotent teardown. Create a new app to reopen after
  shutdown; do not use shutdown as a temporary lifecycle pause.
- The default worker uses concurrency 1, prefetch multiplier 1, and no process
  signal handlers. Configure it with the ordinary `StemWorkerConfig`.
- The worker coordinator runs in the calling isolate. Inline async handlers can
  use Flutter plugins and application services. CPU-heavy handlers should use
  Stem's normal isolate execution mode and its isolate-safe entrypoint contract.
  That does not require a second Flutter-specific worker entrypoint.
- SQLite operations themselves use the adapter's synchronous database driver.
  Moving a task into an isolate does not move database coordination there.

An isolate is not an Android service or an iOS background task. The OS may
suspend or terminate the process without a shutdown callback. This package does
not promise execution while suspended, schedule OS background work, or make
side effects exactly-once.

## Background execution and Workmanager

The boundary is **app-owned scheduling, Stem-owned execution**.
Keep Workmanager registration, constraints, native configuration, and scheduler
retry policy in your application. Its standard callback should delegate Stem
task execution to a scheduler-neutral core runner, not implement another
worker protocol.

Use core `app.runUntilIdle(budget: ..., cancellation: ...)` on a fresh app in
that callback. It stops admission when idle, at the admission deadline, or when
cancellation is requested, drains active work, and closes the one-shot app.
It does not grant OS execution time or force arbitrary inline work to stop.
See the [background execution guide](doc/background-execution.md) for the
contract, outcome mapping, Android Workmanager example, and platform limits.

## Diagnostics use core Stem APIs

```dart
final page = await app.backend.listTaskStatuses(
  TaskStatusListRequest(queue: 'my-queue', limit: 40),
);
final pending = await app.broker.pendingCount('my-queue');
final inflight = await app.broker.inflightCount('my-queue');

final subscription = app.worker.events.listen((event) {
  print(event.type);
});
// Cancel when the observer is finished.
await subscription.cancel();
```

Use `getTaskStatus` or typed `waitFor` for ordinary application task results.
Queue inspection, task records, worker events, heartbeats, logging, and control
commands already belong to core Stem; Flutter does not wrap them in new models
or reinterpret their status.

The example includes its own queue debug UI. Refresh scheduling, screen/app
visibility, job labels, and formatting are presentation concerns and stay in
that example. They are not required to execute or observe a task. An observation
owner must finish pending reads before its app closes the stores.

## Removed APIs and migration

This cleanup removes the old APIs rather than retaining compatibility wrappers:

| Removed API | Replacement |
| --- | --- |
| `StemFlutterQueueMonitor`, queue snapshots, tracked-job models | Core task records/queue inspection; example-owned debug presentation |
| `StemFlutterWorkerHost`, worker signals and status enum | Core `StemApp`, `Worker`, and `WorkerEvent` |
| Dependency initialization and background asset payload helpers | Adapter-specific setup where required; no custom isolate asset protocol |

Register tasks or modules once, explicitly start the returned app, enqueue and
observe through core APIs, and shut down the app when its application-level owner
is finished. Custom whole-runtime isolates, if required, are application
architecture—not a second execution API imposed by this package.

Ormed-backed SQLite stores still need their dependency assets initialized; that
setup belongs to `stem_flutter_sqlite`, not this adapter-neutral package.

See `packages/stem/example/flutter_stem_example` for an application-owned,
SQLite-backed example.
