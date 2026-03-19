// Stores workflow state in a SQLite file using the stem_sqlite adapter.
// Run with: dart run example/workflows/sqlite_store.dart

import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_sqlite/stem_sqlite.dart';

Future<void> main() async {
  final databaseFile = File('workflow.sqlite');
  final sqliteExample = Flow<String>(
    name: 'sqlite.example',
    build: (flow) {
      flow.step('greet', (ctx) async => 'Persisted to SQLite');
    },
  );
  final sqliteExampleRef = sqliteExample.ref0();
  final app = await StemWorkflowApp.fromUrl(
    'sqlite://${databaseFile.path}',
    adapters: const [StemSqliteAdapter()],
    flows: [sqliteExample],
  );

  try {
    final runId = await sqliteExampleRef.call().startWithApp(app);
    final result = await sqliteExampleRef.waitFor(app, runId);
    print('Workflow $runId finished with result: ${result?.value}');
  } finally {
    await app.close();
    if (databaseFile.existsSync()) {
      databaseFile.deleteSync();
    }
  }
}
