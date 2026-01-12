import 'package:stem/src/control/revoke_store.dart';
import 'package:test/test.dart';

void main() {
  group('RevokeEntry', () {
    test('round trips through json', () {
      final issuedAt = DateTime.utc(2025, 1, 2, 3, 4, 5);
      final expiresAt = DateTime.utc(2025, 1, 2, 4, 4, 5);
      final entry = RevokeEntry(
        namespace: 'default',
        taskId: 'task-1',
        version: 42,
        issuedAt: issuedAt,
        terminate: true,
        reason: 'duplicate',
        requestedBy: 'tester',
        expiresAt: expiresAt,
      );

      final decoded = RevokeEntry.fromJson(entry.toJson());

      expect(decoded.namespace, equals('default'));
      expect(decoded.taskId, equals('task-1'));
      expect(decoded.version, equals(42));
      expect(decoded.issuedAt, equals(issuedAt));
      expect(decoded.terminate, isTrue);
      expect(decoded.reason, equals('duplicate'));
      expect(decoded.requestedBy, equals('tester'));
      expect(decoded.expiresAt, equals(expiresAt));
    });

    test('isExpired respects expiry time', () {
      final now = DateTime.utc(2025, 2, 1, 12);
      final entry = RevokeEntry(
        namespace: 'default',
        taskId: 'task-1',
        version: 1,
        issuedAt: now,
        expiresAt: now.subtract(const Duration(minutes: 1)),
      );

      expect(entry.isExpired(now), isTrue);
      expect(
        entry.isExpired(now.subtract(const Duration(minutes: 2))),
        isFalse,
      );
    });

    test('copyWith overrides provided fields', () {
      final issuedAt = DateTime.utc(2025);
      final entry = RevokeEntry(
        namespace: 'default',
        taskId: 'task-1',
        version: 1,
        issuedAt: issuedAt,
      );

      final updated = entry.copyWith(taskId: 'task-2', terminate: true);

      expect(updated.namespace, equals('default'));
      expect(updated.taskId, equals('task-2'));
      expect(updated.version, equals(1));
      expect(updated.issuedAt, equals(issuedAt));
      expect(updated.terminate, isTrue);
    });
  });

  test('generateRevokeVersion uses utc microseconds', () {
    final version = generateRevokeVersion();
    expect(version, greaterThan(0));
  });
}
