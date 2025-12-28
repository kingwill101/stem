import 'dart:io';

@Deprecated('Use SqliteConnections/QueryContext from stem_sqlite instead.')
class StemSqliteDatabase {
  StemSqliteDatabase._();

  static Future<StemSqliteDatabase> openFile(
    File file, {
    bool readOnly = false,
  }) async {
    throw UnsupportedError(
      'StemSqliteDatabase is deprecated. '
      'Use SqliteConnections.open(file, readOnly: $readOnly) instead.',
    );
  }
}
