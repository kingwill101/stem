import 'dart:io';

/// Legacy database wrapper kept for backward compatibility.
@Deprecated('Use SqliteConnections/QueryContext from stem_sqlite instead.')
class StemSqliteDatabase {
  /// Creates the legacy wrapper.
  @Deprecated('Use SqliteConnections/QueryContext from stem_sqlite instead.')
  StemSqliteDatabase._();

  /// Throws an [UnsupportedError] in favor of `SqliteConnections`.
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
