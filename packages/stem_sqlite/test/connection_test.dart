import 'dart:io';

import 'package:stem_sqlite/src/connection.dart';
import 'package:test/test.dart';

void main() {
  test(
    'serializes concurrent transactions across SQLite connections',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'stem-sqlite-connection-test-',
      );
      final file = File('${directory.path}/stem.db');
      final connections = await SqliteConnections.open(file);
      final secondConnections = await SqliteConnections.open(file);
      try {
        expect(
          connections.dataSource.options.name,
          isNot(secondConnections.dataSource.options.name),
        );
        await Future.wait(
          List.generate(
            32,
            (index) => (index.isEven ? connections : secondConnections)
                .runInTransaction((_) async {
                  await Future<void>.delayed(const Duration(milliseconds: 1));
                }),
          ),
        );
      } finally {
        await secondConnections.close();
        await connections.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
