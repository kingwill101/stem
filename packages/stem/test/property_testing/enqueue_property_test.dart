import 'package:property_testing/property_testing.dart';
import 'package:stem/stem.dart';
import 'package:test/test.dart';

import 'property_test_helpers.dart';

class _EchoTask extends TaskHandler<Map<String, Object?>> {
  @override
  String get name => 'property.echo';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 0);

  @override
  TaskMetadata get metadata => const TaskMetadata();

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<Map<String, Object?>> call(
    TaskContext context,
    Map<String, Object?> args,
  ) async {
    return args;
  }
}

Generator<Map<String, Object?>> _payloadGen() {
  final entryGen = Gen.string(minLength: 1, maxLength: 8).flatMap(
    (key) => Gen.string(minLength: 0, maxLength: 24).map(
      (value) => MapEntry<String, Object?>(key, value),
    ),
  );
  return Gen.containerOf<Map<String, Object?>, MapEntry<String, Object?>>(
    entryGen,
    (entries) {
      final map = <String, Object?>{};
      for (final entry in entries) {
        map[entry.key] = entry.value;
      }
      return map;
    },
    minLength: 0,
    maxLength: 5,
  );
}

void main() {
  test('enqueue + execute round-trip is stable', () async {
    final broker = InMemoryBroker();
    final backend = InMemoryResultBackend();
    final registry = SimpleTaskRegistry()..register(_EchoTask());
    final worker = Worker(broker: broker, registry: registry, backend: backend);
    await worker.start();

    final stem = Stem(broker: broker, registry: registry, backend: backend);

    final runner = PropertyTestRunner<Map<String, Object?>>(
      _payloadGen(),
      (payload) async {
        final taskId = await stem.enqueue(_EchoTask().name, args: payload);
        final result = await stem.waitForTask<Map<String, Object?>>(
          taskId,
          timeout: const Duration(seconds: 2),
        );
        expect(result?.isSucceeded, isTrue);
        expect(result?.value, equals(payload));
      },
      fastPropertyConfig,
    );

    await expectProperty(
      runner,
      description: 'enqueue/execute round-trip',
    );

    await worker.shutdown();
    await backend.close();
    await broker.close();
  });
}
