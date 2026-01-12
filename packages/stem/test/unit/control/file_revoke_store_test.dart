import 'dart:io';

import 'package:stem/src/control/file_revoke_store.dart';
import 'package:stem/src/control/revoke_store.dart';
import 'package:test/test.dart';

void main() {
  group('FileRevokeStore', () {
    late Directory tempDir;
    late File storeFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stem-revoke-');
      storeFile = File('${tempDir.path}/revokes.jsonl');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('creates file on open when missing', () async {
      final store = await FileRevokeStore.open(storeFile.path);

      expect(storeFile.existsSync(), isTrue);
      final entries = await store.list('default');
      expect(entries, isEmpty);
      await store.close();
    });

    test('upsert respects version ordering and persists', () async {
      final store = await FileRevokeStore.open(storeFile.path);
      final issuedAt = DateTime.utc(2025);

      final first = RevokeEntry(
        namespace: 'default',
        taskId: 'task-1',
        version: 2,
        issuedAt: issuedAt,
      );
      final second = RevokeEntry(
        namespace: 'default',
        taskId: 'task-1',
        version: 1,
        issuedAt: issuedAt,
        terminate: true,
      );

      final applied = await store.upsertAll([first, second]);

      expect(applied.first.version, equals(2));
      expect(applied.last.version, equals(2));

      final lines = storeFile.readAsLinesSync();
      expect(lines.length, equals(1));

      final reopened = await FileRevokeStore.open(storeFile.path);
      final entries = await reopened.list('default');
      expect(entries.single.version, equals(2));
      await reopened.close();
    });

    test('list is ordered by version and pruneExpired persists', () async {
      final store = await FileRevokeStore.open(storeFile.path);
      final now = DateTime.utc(2025, 1, 1, 10);

      await store.upsertAll([
        RevokeEntry(
          namespace: 'default',
          taskId: 'task-1',
          version: 5,
          issuedAt: now,
          expiresAt: now.subtract(const Duration(minutes: 5)),
        ),
        RevokeEntry(
          namespace: 'default',
          taskId: 'task-2',
          version: 2,
          issuedAt: now,
        ),
        RevokeEntry(
          namespace: 'default',
          taskId: 'task-3',
          version: 9,
          issuedAt: now,
        ),
      ]);

      final ordered = await store.list('default');
      expect(ordered.map((e) => e.version).toList(), equals([2, 5, 9]));

      final removed = await store.pruneExpired('default', now);
      expect(removed, equals(1));

      final remaining = await store.list('default');
      expect(remaining.map((e) => e.taskId), equals(['task-2', 'task-3']));

      final lines = storeFile.readAsLinesSync();
      expect(lines.length, equals(2));

      await store.close();
    });
  });
}
