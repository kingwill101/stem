import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'database.g.dart';

@DriftDatabase(include: {'schema/stem_sqlite.drift'})
class StemSqliteDatabase extends _$StemSqliteDatabase {
  StemSqliteDatabase(QueryExecutor executor) : super(executor);

  factory StemSqliteDatabase.openFile(
    File file, {
    bool readOnly = false,
  }) =>
      StemSqliteDatabase(_openConnection(file, readOnly: readOnly));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          if (!details.wasCreated && details.hadUpgrade) {
            // No-op for now; migrations handled via schemaVersion bumps.
          }
          if (!details.isReadOnly) {
            await customStatement('PRAGMA journal_mode=WAL;');
            await customStatement('PRAGMA synchronous=NORMAL;');
          }
        },
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // No upgrades yet; schemaVersion bump will handle future changes.
        },
      );
}

LazyDatabase _openConnection(File file, {bool readOnly = false}) {
  return LazyDatabase(() async {
    if (!readOnly) {
      file.parent.createSync(recursive: true);
    }
    final path = file.path;
    return NativeDatabase.createInBackground(
      path,
      readOnly: readOnly,
      logStatements: false,
    );
  });
}
