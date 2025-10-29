import 'dart:io';

import 'database.dart';

class SqliteConnections {
  SqliteConnections._(this.database);

  final StemSqliteDatabase database;

  StemSqliteDatabase get db => database;

  static Future<SqliteConnections> open(
    File file, {
    bool readOnly = false,
  }) async {
    final db = StemSqliteDatabase.openFile(file, readOnly: readOnly);
    return SqliteConnections._(db);
  }

  Future<T> runInTransaction<T>(
    Future<T> Function(StemSqliteDatabase txn) action,
  ) {
    return database.transaction(() => action(database));
  }

  Future<void> close() => database.close();
}
