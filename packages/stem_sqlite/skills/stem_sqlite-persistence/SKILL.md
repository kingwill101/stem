---
name: stem_sqlite-persistence
description: >-
  Use when configuring Stem's SQLite broker, result backend, migrations,
  workflow store, or transactional local persistence. Match files, namespaces,
  leases, retention, and shutdown across one durable application.
---

# stem_sqlite persistence

## Rules

- Use `SqliteConnections.open(file)` when you need an Ormed connection wrapper;
  it runs migrations before opening the data source. Use
  `SqliteConnections.fromDataSource` only when the caller owns an already
  initialized data source and intentionally does not want migrations.
- Close every owned connection/backend/broker. `close` waits for transactions
  already admitted through `runInTransaction`.
- Prefer separate broker, result-backend, and workflow-store files to reduce
  contention between SQLite writers. The Flutter storage layout requires
  distinct broker/backend paths. Use the same path and namespace when reopening
  each component, not one shared file for all components.
- Prefer exported SQLite factories or the higher-level Flutter SQLite
  bootstrap. Same-file handles may have in-process serialization, but this is
  not cross-process writer coordination or a reason to combine the databases.
- SQLite persistence survives process restarts, not arbitrary in-flight side
  effects. Lease expiry can deliver a task again; make handlers idempotent and
  do not promise exactly-once execution.
- WAL and busy-timeout setup are adapter concerns; do not bypass the package
  factories with an unconfigured raw connection for production queues.
- SQLite is local persistence, not a mobile OS background scheduler. A
  platform callback must reopen the app and explicitly start/recover work.

## Example: persistent workflow host

This Dart VM example creates a new run each time. For an existing run, retain
its ID and use `host.observe(workflow, savedRunId)` instead of submitting again.

```dart
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_sqlite/stem_sqlite.dart';

Future<void> main() async {
  final directory = await Directory('var').create(recursive: true);
  String databaseUrl(String name) => Uri(
    scheme: 'sqlite',
    path: '${directory.absolute.path}/$name.sqlite',
  ).toString();
  final workflow = HostedWorkflow<String, String>(
    name: 'local.greeting',
    run: (context, name) =>
        context.step('greet', () => 'Hello, $name!'),
  );
  final host = await WorkflowHost.create(
    workflows: [workflow],
    createApp: (definitions) => StemWorkflowApp.fromUrl(
      databaseUrl('broker'),
      adapters: const [StemSqliteAdapter()],
      overrides: StemStoreOverrides(
        backend: databaseUrl('backend'),
        workflow: databaseUrl('workflows'),
      ),
      workflows: definitions,
    ),
  );
  try {
    final recovery = await host.recover();
    if (recovery.errors.isNotEmpty) {
      throw StateError('Some existing runs could not be recovered.');
    }
    final run = await host.submit(workflow, 'Ada');
    print('Retain this run ID: ${run.id}');
    print(await run.result);
  } finally {
    await host.close();
  }
}
```

`recover` scans a bounded batch; it is not a promise to drain every run.
Reopen the same storage with compatible definitions and codecs. In Flutter,
obtain an application-owned storage directory rather than using a relative
server path.

## Low-level connection and transaction

```dart
import 'dart:io';
import 'package:stem_sqlite/stem_sqlite.dart';

Future<void> main() async {
  final connections = await SqliteConnections.open(
    File('var/stem.sqlite'),
  );
  try {
    await connections.runInTransaction((context) async {
      // Use Ormed queries against this transaction context.
    });
  } finally {
    await connections.close();
  }
}
```

For a full queue application, use the package's documented
`StemFlutterSqlite.createApp` bootstrap from `stem_flutter_sqlite` in Flutter,
or construct the exported `sqliteBrokerFactory`,
`sqliteResultBackendFactory`, and workflow-store factory with one explicit
storage policy in a Dart VM/server application.

## Validation checklist

1. Exercise migration startup against a new file and an upgraded file.
2. Restart while a lease is active and verify recovery plus idempotency.
3. Verify retention and cleanup do not remove results before consumers need
   them.
4. Ensure all stores and connections close before deleting or replacing files.
