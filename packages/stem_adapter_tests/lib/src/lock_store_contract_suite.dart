import 'dart:async';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

/// Settings that tune the lock store contract test suite.
class LockStoreContractSettings {
  /// Creates lock store contract settings.
  const LockStoreContractSettings({
    this.initialTtl = const Duration(milliseconds: 200),
    this.expiryBackoff = const Duration(milliseconds: 200),
  });

  /// TTL used when verifying expiry behaviour.
  final Duration initialTtl;

  /// Additional wait time to ensure the lock expires in the backend.
  final Duration expiryBackoff;
}

/// Factory hooks used by the lock store contract test suite.
class LockStoreContractFactory {
  /// Creates a lock store contract factory.
  const LockStoreContractFactory({required this.create, this.dispose});

  /// Creates a fresh lock store instance for each test case.
  final Future<LockStore> Function() create;

  /// Optional disposer invoked after each test.
  final FutureOr<void> Function(LockStore store)? dispose;
}

/// Runs contract tests covering the required LockStore semantics.
void runLockStoreContractTests({
  required String adapterName,
  required LockStoreContractFactory factory,
  LockStoreContractSettings settings = const LockStoreContractSettings(),
}) {
  group('$adapterName lock store contract', () {
    LockStore? store;

    setUp(() async {
      store = await factory.create();
    });

    tearDown(() async {
      final current = store;
      if (current != null) {
        if (factory.dispose != null) {
          await factory.dispose!(current);
        }
      }
      store = null;
    });

    test('ownerOf reports the current owner while lock is held', () async {
      final current = store!;
      final key = _lockKey('owner-of');
      final lock = await current.acquire(
        key,
        owner: 'owner-1',
        ttl: settings.initialTtl,
      );
      expect(lock, isNotNull);

      final owner = await current.ownerOf(key);
      expect(owner, equals('owner-1'));

      await lock!.release();
      final afterRelease = await current.ownerOf(key);
      expect(afterRelease, isNull);
    });

    test(
      'release rejects mismatched owners without dropping the lock',
      () async {
        final current = store!;
        final key = _lockKey('mismatch');
        final lock = await current.acquire(key, owner: 'owner-a');
        expect(lock, isNotNull);

        final released = await current.release(key, 'owner-b');
        expect(released, isFalse);

        final stillHeld = await current.ownerOf(key);
        expect(stillHeld, equals('owner-a'));

        await lock!.release();
      },
    );

    test('locks expire after TTL allowing reacquisition', () async {
      final current = store!;
      final key = _lockKey('ttl-expiry');
      final lock = await current.acquire(
        key,
        owner: 'owner-expiring',
        ttl: settings.initialTtl,
      );
      expect(lock, isNotNull);

      await Future<void>.delayed(settings.initialTtl + settings.expiryBackoff);

      final owner = await current.ownerOf(key);
      expect(owner, isNull);

      final reacquired = await current.acquire(key, owner: 'owner-new');
      expect(reacquired, isNotNull);
      await reacquired!.release();
    });

    test('renew extends the lock TTL', () async {
      final current = store!;
      final key = _lockKey('renew');
      final lock = await current.acquire(
        key,
        owner: 'owner-renew',
        ttl: settings.initialTtl,
      );
      expect(lock, isNotNull);

      final extended = Duration(
        milliseconds: settings.initialTtl.inMilliseconds * 4,
      );
      final renewed = await lock!.renew(extended);
      expect(renewed, isTrue);

      await Future<void>.delayed(settings.initialTtl + settings.expiryBackoff);
      final owner = await current.ownerOf(key);
      expect(owner, equals('owner-renew'));

      await lock.release();
    });

    test('renew fails after lock expiry', () async {
      final current = store!;
      final key = _lockKey('renew-expired');
      final lock = await current.acquire(
        key,
        owner: 'owner-expired',
        ttl: settings.initialTtl,
      );
      expect(lock, isNotNull);

      await Future<void>.delayed(settings.initialTtl + settings.expiryBackoff);
      final renewed = await lock!.renew(settings.initialTtl);
      expect(renewed, isFalse);

      final owner = await current.ownerOf(key);
      expect(owner, isNull);
    });
  });
}

String _lockKey(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_counter++}';

int _counter = 0;
