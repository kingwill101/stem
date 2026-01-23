import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stem_adapter_tests/stem_adapter_tests.dart';
import 'package:stem_sqlite/stem_sqlite.dart';

void main() {
  final sqliteDirectories = Expando<Directory>('sqlite-directory');

  final sqliteFactory = WorkflowStoreContractFactory(
    create: (clock) async {
      final tmpDir = await Directory.systemTemp.createTemp('wf-sqlite');
      final file = File(p.join(tmpDir.path, 'workflow.sqlite'));
      final store = await SqliteWorkflowStore.open(file, clock: clock);
      sqliteDirectories[store] = tmpDir;
      return store;
    },
    dispose: (store) async {
      if (store is SqliteWorkflowStore) {
        await store.close();
        final directory = sqliteDirectories[store];
        if (directory != null && directory.existsSync()) {
          directory.deleteSync(recursive: true);
        }
      }
    },
  );
  runWorkflowStoreContractTests(adapterName: 'sqlite', factory: sqliteFactory);
  runWorkflowScriptFacadeTests(adapterName: 'sqlite', factory: sqliteFactory);
}
