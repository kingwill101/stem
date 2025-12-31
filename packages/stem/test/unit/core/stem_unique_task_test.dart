import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('Stem unique tasks', () {
    test(
      'deduplicates repeated enqueues and records duplicate metadata',
      () async {
        final broker = InMemoryBroker(
          delayedInterval: const Duration(milliseconds: 5),
          claimInterval: const Duration(milliseconds: 20),
        );
        final backend = InMemoryResultBackend();
        final registry = SimpleTaskRegistry()
          ..register(
            FunctionTaskHandler<void>(
              name: 'demo.unique',
              entrypoint: (_, _) async {
                return null;
              },
            ),
          );
        final coordinator = UniqueTaskCoordinator(
          lockStore: InMemoryLockStore(),
          defaultTtl: const Duration(seconds: 10),
        );
        final stem = Stem(
          broker: broker,
          registry: registry,
          backend: backend,
          uniqueTaskCoordinator: coordinator,
        );

        const options = TaskOptions(
          unique: true,
          uniqueFor: Duration(seconds: 30),
        );
        final firstId = await stem.enqueue(
          'demo.unique',
          args: const {'value': 1},
          options: options,
        );

        expect(firstId, isNotEmpty);
        expect(await broker.pendingCount('default'), equals(1));

        final duplicateId = await stem.enqueue(
          'demo.unique',
          args: const {'value': 1},
          options: options,
        );

        expect(duplicateId, equals(firstId));
        expect(await broker.pendingCount('default'), equals(1));

        final status = await backend.get(firstId);
        expect(status, isNotNull);
        final meta = status!.meta;
        expect(meta[UniqueTaskMetadata.key], isA<String>());
        final duplicates =
            meta[UniqueTaskMetadata.duplicates] as List<Object?>?;
        expect(duplicates, isA<List<Object?>>());
        expect(duplicates!.length, equals(1));

        broker.dispose();
      },
    );
  });
}
