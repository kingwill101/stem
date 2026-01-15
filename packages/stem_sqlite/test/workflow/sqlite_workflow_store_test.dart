import 'dart:io';

import 'package:ormed/ormed.dart';
import 'package:ormed_sqlite/ormed_sqlite.dart';
import 'package:stem/stem.dart';
import 'package:stem_sqlite/stem_sqlite.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'stem_sqlite_workflow_store_test',
    );
    dbFile = File('${tempDir.path}/workflow.db');
  });

  tearDown(() async {
    if (dbFile.existsSync()) {
      await dbFile.delete();
    }
    await tempDir.delete(recursive: true);
  });

  test('fromDataSource runs migrations', () async {
    ensureSqliteDriverRegistration();
    final dataSource = DataSource(
      DataSourceOptions(
        driver: SqliteDriverAdapter.file(dbFile.path),
        registry: buildOrmRegistry(),
        database: dbFile.path,
      ),
    );
    final store = await SqliteWorkflowStore.fromDataSource(dataSource);
    try {
      final runId = await store.createRun(
        workflow: 'datasource-workflow',
        params: const {'value': 1},
      );

      final state = await store.get(runId);
      expect(state, isNotNull);
      expect(state!.status, WorkflowStatus.running);
    } finally {
      await store.close();
      await dataSource.dispose();
    }
  });
}
