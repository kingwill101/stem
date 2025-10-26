import 'dart:io';

import 'package:drift/drift.dart';

import 'database.dart';

class SqliteConnections {
  SqliteConnections._(this.database);

  final StemSqliteDatabase database;

  static Future<SqliteConnections> open(
    File file, {
    bool readOnly = false,
  }) async {
    final db = StemSqliteDatabase.openFile(file, readOnly: readOnly);
    return SqliteConnections._(db);
  }

  Future<void> close() => database.close();
}
