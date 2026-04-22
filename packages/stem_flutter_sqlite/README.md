# stem_flutter_sqlite

SQLite-specific Flutter helpers for Stem.

This package builds on `stem_flutter` and handles the SQLite pieces that are
awkward to repeat in every mobile app:

- resolving an application-owned storage layout
- opening a foreground Stem runtime backed by SQLite files
- preloading and forwarding the Flutter assets needed by background isolates
- reconstructing broker and backend handles inside a worker isolate
- providing a convenience launcher for SQLite worker isolates

Use this package when you want a single-device or local-first Flutter setup
with Stem and SQLite.

## Installation

```yaml
dependencies:
  stem_flutter_sqlite: ^0.1.0
```

`stem_flutter_sqlite` depends on `stem_flutter`, `stem_sqlite`, and
`path_provider`.

## What This Package Includes

- `StemFlutterStorageLayout`: resolves broker and backend files under an
  application-owned directory
- `StemFlutterSqliteRuntime`: opens the foreground broker, backend, and Stem
  producer runtime
- `StemFlutterSqliteWorkerBootstrap`: isolate-safe bootstrap payload for worker
  isolates
- `StemFlutterSqliteWorkerStores`: reopens the worker-side SQLite stores from
  the bootstrap payload
- `StemFlutterSqliteWorkerLauncher`: convenience wrapper around
  `StemFlutterWorkerHost.spawn(...)`

The package also handles the internal Flutter dependency bootstrap needed by
`time_machine2`. There is no separate public time-machine setup API to wire by
hand.

## Recommended Runtime Model

For mobile apps, the intended setup is:

1. The UI isolate opens a `StemFlutterSqliteRuntime`.
2. A separate worker isolate reopens the broker and result backend using
   `StemFlutterSqliteWorkerBootstrap`.
3. The UI uses `StemFlutterQueueMonitor` from `stem_flutter` to observe queue
   depth, recent jobs, and worker heartbeats.
4. The broker and result backend live in separate SQLite files to reduce write
   contention.

## Quick Start

### UI isolate

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:stem/stem.dart';
import 'package:stem_flutter/stem_flutter.dart';
import 'package:stem_flutter_sqlite/stem_flutter_sqlite.dart';

Future<void> bootstrap(List<TaskHandler<Object?>> taskHandlers) async {
  WidgetsFlutterBinding.ensureInitialized();

  final layout = await StemFlutterStorageLayout.applicationSupport(
    directoryName: 'stem_mobile_demo',
  );

  final runtime = await StemFlutterSqliteRuntime.open(
    layout: layout,
    tasks: taskHandlers,
    brokerPollInterval: const Duration(milliseconds: 250),
    brokerVisibilityTimeout: const Duration(seconds: 6),
  );

  final rootIsolateToken = RootIsolateToken.instance!;
  final workerHost = await StemFlutterSqliteWorkerLauncher.spawn(
    entrypoint: workerMain,
    layout: layout,
    rootIsolateToken: rootIsolateToken,
    brokerPollInterval: const Duration(milliseconds: 250),
    brokerSweeperInterval: const Duration(seconds: 2),
    brokerVisibilityTimeout: const Duration(seconds: 6),
  );

  final monitor = StemFlutterQueueMonitor(
    backend: runtime.backend,
    broker: runtime.broker,
    queueName: 'mobile-demo',
    workerId: 'mobile-worker',
  )..bindWorkerSignals(workerHost.signals);

  await monitor.start();
}
```

### Worker isolate

```dart
import 'dart:isolate';

import 'package:stem/stem.dart';
import 'package:stem_flutter/stem_flutter.dart';
import 'package:stem_flutter_sqlite/stem_flutter_sqlite.dart';

// Assume taskHandlers is the same List<TaskHandler<Object?>> your UI isolate
// uses when opening StemFlutterSqliteRuntime.
Future<void> workerMain(Map<String, Object?> message) async {
  final bootstrap = StemFlutterSqliteWorkerBootstrap.fromMessage(message);
  await bootstrap.initializeBackgroundDependencies();

  final stores = await StemFlutterSqliteWorkerStores.open(bootstrap);
  final commands = ReceivePort();

  final worker = Worker(
    broker: stores.broker,
    backend: stores.backend,
    tasks: taskHandlers,
    queue: 'mobile-demo',
    consumerName: 'mobile-worker',
  );

  await worker.start();
  bootstrap.sendPort.send(
    StemFlutterWorkerSignal.ready(
      commandPort: commands.sendPort,
      detail: 'Worker isolate ready.',
    ).toMessage(),
  );

  await for (final dynamic command in commands) {
    if (command is Map && command['type'] == 'shutdown') {
      break;
    }
  }

  await worker.shutdown();
  await stores.close();
  commands.close();
}
```

## Mobile Notes

- Run the worker in a separate isolate. On mobile, that is the main reason this
  package exists.
- Keep the broker and result backend in separate SQLite files. A single file
  works for toy setups, but contention becomes much easier to hit.
- If you hot-restart while work is inflight, the broker may need one
  visibility-timeout cycle before a task is claimable again.
- `SqliteResultBackend.watch(taskId)` is process-local. For UI monitoring, poll
  `getTaskStatus()` or `listTaskStatuses()` instead.
- This package does not provide OS-managed background scheduling. If you need
  true background execution, pair Stem with a platform-specific job runner.

## Example

See `packages/stem/example/flutter_stem_example` for a complete working app
that uses:

- `StemFlutterStorageLayout`
- `StemFlutterSqliteRuntime`
- `StemFlutterSqliteWorkerLauncher`
- `StemFlutterQueueMonitor`
