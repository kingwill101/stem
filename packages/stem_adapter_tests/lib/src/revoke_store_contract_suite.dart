import 'dart:async';

import 'package:stem/stem.dart';
import 'package:stem_adapter_tests/src/contract_capabilities.dart';
import 'package:test/test.dart';

/// Settings that tune the revoke store contract test suite.
class RevokeStoreContractSettings {
  /// Creates revoke store contract settings.
  const RevokeStoreContractSettings({
    this.capabilities = const RevokeStoreContractCapabilities(),
  });

  /// Feature capability flags for optional contract assertions.
  final RevokeStoreContractCapabilities capabilities;
}

/// Factory hooks used by the revoke store contract test suite.
class RevokeStoreContractFactory {
  /// Creates a revoke store contract factory.
  const RevokeStoreContractFactory({required this.create, this.dispose});

  /// Creates a fresh revoke store instance for each test case.
  final Future<RevokeStore> Function() create;

  /// Optional disposer invoked after each test.
  final FutureOr<void> Function(RevokeStore store)? dispose;
}

/// Runs contract tests covering the required RevokeStore semantics.
void runRevokeStoreContractTests({
  required String adapterName,
  required RevokeStoreContractFactory factory,
  RevokeStoreContractSettings settings = const RevokeStoreContractSettings(),
}) {
  group('$adapterName revoke store contract', () {
    RevokeStore? store;

    setUp(() async {
      store = await factory.create();
    });

    tearDown(() async {
      final current = store;
      if (current != null && factory.dispose != null) {
        await factory.dispose!(current);
      }
      store = null;
    });

    test(
      'upsert/list stores entries by namespace and version ordering',
      () async {
        final current = store!;
        final now = DateTime.utc(2026, 2, 24, 10, 45);
        const namespace = 'stem-contract';
        final entries = [
          RevokeEntry(
            namespace: namespace,
            taskId: 'task-2',
            version: 2,
            issuedAt: now,
          ),
          RevokeEntry(
            namespace: namespace,
            taskId: 'task-1',
            version: 1,
            issuedAt: now,
          ),
        ];

        final applied = await current.upsertAll(entries);
        expect(
          applied.map((entry) => entry.taskId),
          containsAll(['task-1', 'task-2']),
        );

        final listed = await current.list(namespace);
        expect(listed.map((entry) => entry.version).toList(), equals([1, 2]));
        expect(listed.every((entry) => entry.namespace == namespace), isTrue);
      },
    );

    test('upsert preserves newer entries and ignores stale versions', () async {
      final current = store!;
      final now = DateTime.utc(2026, 2, 24, 11);
      const namespace = 'stem-contract';
      const taskId = 'task-stale';
      final first = RevokeEntry(
        namespace: namespace,
        taskId: taskId,
        version: 10,
        issuedAt: now,
        reason: 'newer',
      );
      final stale = RevokeEntry(
        namespace: namespace,
        taskId: taskId,
        version: 9,
        issuedAt: now.subtract(const Duration(minutes: 1)),
        reason: 'stale',
      );

      await current.upsertAll([first]);
      final applied = await current.upsertAll([stale]);
      expect(applied.single.version, 10);
      expect(applied.single.reason, 'newer');

      final listed = await current.list(namespace);
      expect(listed.single.version, 10);
      expect(listed.single.reason, 'newer');
    });

    test('upsert replaces entries when a higher version is provided', () async {
      final current = store!;
      final now = DateTime.utc(2026, 2, 24, 11, 5);
      const namespace = 'stem-contract';
      const taskId = 'task-upgrade';
      await current.upsertAll([
        RevokeEntry(
          namespace: namespace,
          taskId: taskId,
          version: 4,
          issuedAt: now,
        ),
      ]);

      final applied = await current.upsertAll([
        RevokeEntry(
          namespace: namespace,
          taskId: taskId,
          version: 5,
          issuedAt: now.add(const Duration(seconds: 30)),
          terminate: true,
          reason: 'superseded',
        ),
      ]);

      expect(applied.single.version, 5);
      expect(applied.single.terminate, isTrue);
      expect(applied.single.reason, 'superseded');
    });

    test(
      'pruneExpired removes expired records only within target namespace',
      () async {
        final current = store!;
        final now = DateTime.utc(2026, 2, 24, 11, 10);
        const namespaceA = 'stem-contract-a';
        const namespaceB = 'stem-contract-b';
        await current.upsertAll([
          RevokeEntry(
            namespace: namespaceA,
            taskId: 'expired',
            version: 1,
            issuedAt: now.subtract(const Duration(minutes: 2)),
            expiresAt: now.subtract(const Duration(seconds: 1)),
          ),
          RevokeEntry(
            namespace: namespaceA,
            taskId: 'active',
            version: 2,
            issuedAt: now,
            expiresAt: now.add(const Duration(minutes: 5)),
          ),
          RevokeEntry(
            namespace: namespaceA,
            taskId: 'no-expiry',
            version: 4,
            issuedAt: now,
          ),
          RevokeEntry(
            namespace: namespaceB,
            taskId: 'other-namespace',
            version: 3,
            issuedAt: now.subtract(const Duration(minutes: 1)),
            expiresAt: now.subtract(const Duration(seconds: 1)),
          ),
        ]);

        final pruned = await current.pruneExpired(namespaceA, now);
        expect(pruned, 1);

        final listedA = await current.list(namespaceA);
        expect(
          listedA.map((entry) => entry.taskId),
          equals(['active', 'no-expiry']),
        );
        final listedB = await current.list(namespaceB);
        expect(
          listedB.map((entry) => entry.taskId),
          equals(['other-namespace']),
        );
      },
      skip: _skipUnless(
        settings.capabilities.verifyPruneExpired,
        'Adapter disabled pruneExpired capability checks.',
      ),
    );
  });
}

Object _skipUnless(bool enabled, String reason) => enabled ? false : reason;
