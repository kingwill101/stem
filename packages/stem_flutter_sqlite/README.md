# stem_flutter_sqlite

Durable local SQLite storage for **the ordinary Stem API in Flutter**.

`StemFlutterSqlite.createApp()` returns a core `StemApp` with its producer,
worker, and result observer sharing managed SQLite stores. There is no required
custom worker isolate, port protocol, second task registry, or manual database
handle lifecycle.

Version 0.3.0 requires Stem `>=0.4.1 <0.5.0`,
`stem_flutter >=0.3.0 <0.4.0`, and `stem_sqlite >=0.2.2 <0.3.0` for bounded
execution and safe consumer teardown. It replaces the legacy runtime helpers.

## Getting started

```dart
import 'package:stem_flutter_sqlite/stem_flutter_sqlite.dart';

final syncTask = TaskDefinition<String, String>(
  name: 'sync',
  encodeArgs: (account) => {'account': account},
  decodeArgs: (args) => args['account']! as String,
);

Future<StemApp> openApp() async {
  final app = await StemFlutterSqlite.createApp(
    module: StemModule(
      tasks: [
        syncTask.handler(
          entrypoint: (context, account) async {
            // Perform your asynchronous, idempotent sync here.
            return 'Synced $account';
          },
        ),
      ],
    ),
  );
  try {
    await app.start(); // Creating an app never starts consumption implicitly.
    return app;
  } catch (_) {
    await app.shutdown();
    rethrow;
  }
}

Future<void> enqueueSync(StemApp app) async {
  final id = await syncTask.enqueue(app, 'account-123');
  final result = await syncTask.waitFor(app, id);
  print(result?.value);
}
```

Keep the returned app at application scope, inject it into screens/services, and
call `app.shutdown()` when that owner is finished. Shutdown closes the worker,
backend, and broker once. A new app can reopen the same files.

The package re-exports `stem_flutter` and the stable core Stem API. Existing
`app.enqueue`, `app.enqueueCall`, `app.waitForTask`, `app.getTaskStatus`,
`app.registerModule`, and `app.canvas` code works unchanged.

## Storage and configuration

By default, files live under the application support directory:

```text
stem_flutter/
  broker.sqlite
  backend.sqlite
```

The separate files preserve the adapter's existing layout and reduce competition
between queue and result writes. Existing default-layout data does not need to
be moved. To reuse a custom directory, supply its existing layout.

```dart
final app = await StemFlutterSqlite.createApp(
  module: myModule,
  layout: myExistingLayout, // Optional; defaults to application support.
  storage: const StemFlutterSqliteConfig(
    namespace: 'my-app',
    resultTtl: Duration(days: 7),
  ),
  workerConfig: const StemWorkerConfig(concurrency: 2),
);
```

`StemFlutterSqliteConfig` is the single source for broker/backend namespace,
visibility timeout, polling, maintenance, and retention. Defaults match the
underlying SQLite adapter rather than the old example's short leases and
effectively disabled result cleanup. Worker settings use core
`StemWorkerConfig`; queues are inferred from modules as in Stem.

Application-support directory names and helper file names must be single names,
not paths. Use `StemFlutterStorageLayout.forRoot` for an explicit root, or the
explicit layout constructor for advanced file paths.

## Mobile behavior

- The worker coordinator and database connections live in the calling isolate.
  Async inline handlers can use Flutter plugins. For CPU-heavy task bodies,
  select core Stem's isolate execution mode instead of blocking the UI isolate.
  The SQLite driver itself is synchronous; expensive database work still affects
  the isolate that owns the coordinator.
- Persisted queued tasks and results survive reopening, subject to retention.
- Interrupted deliveries become eligible for recovery after their visibility
  lease expires. A handler may run again even if its previous side effect
  succeeded. Use idempotent handlers.
- OS suspension and process termination are normal. Neither SQLite persistence
  nor a Dart isolate guarantees background execution. OS scheduling is outside
  this package.
- Do not call `shutdown()` on every inactive/paused transition. It is final
  teardown, not a resumable pause.

### Background scheduler integration

The app owns Workmanager or other native scheduler registration; Stem should
own execution within the granted window. SQLite is the shared durable queue,
not the OS scheduler. A callback must open its own handles with the same paths,
namespace, and task module; it cannot reuse a foreground Ormed data source
across isolates.

Use the returned core app directly:

```dart
final app = await StemFlutterSqlite.createApp(module: myModule);
final outcome = await app.runUntilIdle(
  budget: const Duration(seconds: 30),
  shutdownReserve: const Duration(seconds: 5),
);
// Inspect outcome.reason; this app and its owned stores are now closed.
```

Do not call `start()` before `runUntilIdle`. Its budget limits new admissions,
not arbitrary active handler duration; active work must drain safely. See the
[background execution guide](../stem_flutter/doc/background-execution.md) for
callback-local initialization, cancellation, retry/wakeup ownership, and limits
on heavy workloads while minimized.

For diagnostics, use core Stem APIs such as `app.backend.listTaskStatuses`,
`app.broker.pendingCount`, `app.broker.inflightCount`, and `app.worker.events`.
The example owns its debug dashboard and presentation lifecycle. No Flutter
monitor, snapshot model, or worker-status protocol is required.

## Migration

The following legacy APIs and wiring have been removed:

- `StemFlutterSqliteRuntime.open` for a producer-only client;
- an app-written worker bootstrap/command loop;
- root isolate tokens, dependency-asset payloads, and duplicated store options;
- manually binding worker-host signals to a queue monitor.

Use `StemFlutterSqlite.createApp` instead and register tasks once. Keep your
existing `TaskDefinition`, `StemModule`, and task invocation APIs. The old
producer runtime, launcher, worker stores, and bootstrap types are not retained
as compatibility wrappers. If you supply stores manually, use core
`StemBrokerFactory`/`StemBackendFactory` with `StemFlutter.createApp` or core
bootstrap directly. Caller-owned Ormed data sources can still be wrapped by
`SqliteBroker.fromDataSource` and `SqliteResultBackend.fromDataSource` from
`stem_sqlite`; the factories determine adapter disposal, and the data source
remains caller-owned.

Call `await StemFlutterSqlite.initialize()` before manually opening those
Ormed-backed stores. Ormed initializes Carbonized, which needs Flutter assets
for its TimeMachine dependency. The convenience `createApp` handles this
automatically; adapter-neutral `StemFlutter.createApp` does not initialize ORM
dependencies.

Workflow composition remains available through core Stem APIs. Durable workflows
also require a workflow store such as `sqliteWorkflowStoreFactory` from
`stem_sqlite`; the task result backend alone is not a workflow store. No workflow
storage is silently substituted by this task bootstrap.

See `packages/stem/example/flutter_stem_example` for the complete mobile example.

## Tests

Run Flutter tests from this package directory so Flutter includes dependency
assets and SQLite native assets:

```bash
cd packages/stem_flutter_sqlite
flutter test
```
