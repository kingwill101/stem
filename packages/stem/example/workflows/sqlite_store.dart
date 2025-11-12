// Stores workflow state in a SQLite file using the stem_sqlite adapter.
// Run with: dart run example/workflows/sqlite_store.dart

import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_sqlite/stem_sqlite.dart';

Future<void> main() async {
  final databaseFile = File('workflow.sqlite');
  final app = await StemWorkflowApp.create(
    flows: [
      Flow(
        name: 'sqlite.example',
        build: (flow) {
          flow.step('greet', (ctx) async => 'Persisted to SQLite');
        },
      ),
    ],
    storeFactory: sqliteWorkflowStoreFactory(databaseFile),
  );

  try {
    final runId = await app.startWorkflow('sqlite.example');
    final state = await app.waitForCompletion(runId);
    print('Workflow $runId finished with result: ${state?.result}');
  } finally {
    await app.shutdown();
    if (databaseFile.existsSync()) {
      databaseFile.deleteSync();
    }
  }
}
