import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('UniqueTaskCoordinator', () {
    test('acquires and releases unique lock', () async {
      final coordinator = UniqueTaskCoordinator(
        lockStore: InMemoryLockStore(),
        defaultTtl: const Duration(seconds: 5),
        namespace: 'test:unique',
      );
      final envelope = Envelope(name: 'demo.task', args: const {});
      final claim = await coordinator.acquire(
        envelope: envelope,
        options: const TaskOptions(unique: true),
      );
      expect(claim.isAcquired, isTrue);
      expect(claim.uniqueKey, isNotEmpty);
      final released = await coordinator.release(claim.uniqueKey, claim.owner);
      expect(released, isTrue);
    });

    test('detects duplicate attempts and returns existing task id', () async {
      final coordinator = UniqueTaskCoordinator(
        lockStore: InMemoryLockStore(),
        defaultTtl: const Duration(seconds: 5),
        namespace: 'test:unique',
      );
      final first = Envelope(name: 'demo.task', args: const {'value': 1});
      const options = TaskOptions(unique: true);
      final claim1 = await coordinator.acquire(
        envelope: first,
        options: options,
      );
      expect(claim1.isAcquired, isTrue);

      final duplicate = Envelope(name: 'demo.task', args: const {'value': 1});
      final claim2 = await coordinator.acquire(
        envelope: duplicate,
        options: options,
      );
      expect(claim2.isAcquired, isFalse);
      expect(claim2.existingTaskId, equals(first.id));
    });

    test('respects explicit unique key override in metadata', () async {
      final coordinator = UniqueTaskCoordinator(
        lockStore: InMemoryLockStore(),
        defaultTtl: const Duration(seconds: 5),
      );
      final envelope = Envelope(
        name: 'demo.task',
        args: const {'value': 1},
        meta: const {UniqueTaskMetadata.override: 'custom-key'},
      );
      final claim = await coordinator.acquire(
        envelope: envelope,
        options: const TaskOptions(unique: true),
      );
      expect(claim.isAcquired, isTrue);
      expect(claim.uniqueKey, equals('custom-key'));
    });
  });
}
