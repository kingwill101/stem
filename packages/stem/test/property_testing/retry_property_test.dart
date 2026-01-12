import 'package:property_testing/property_testing.dart';
import 'package:stem/stem.dart';
import 'package:test/test.dart';

import 'property_test_helpers.dart';

class _FlakyTask extends TaskHandler<String> {
  @override
  String get name => 'property.flaky';

  @override
  TaskOptions get options => const TaskOptions(
        maxRetries: 3,
        retryPolicy: TaskRetryPolicy(
          defaultDelay: Duration(milliseconds: 10),
          backoff: false,
          jitter: false,
        ),
      );

  @override
  TaskMetadata get metadata => const TaskMetadata();

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<String> call(TaskContext context, Map<String, Object?> args) async {
    final failures = (args['failures'] as num?)?.toInt() ?? 0;
    if (context.attempt < failures) {
      throw StateError('simulated failure');
    }
    return 'ok';
  }
}

void main() {
  test('retry semantics converge based on max retries', () async {
    final broker = InMemoryBroker();
    final backend = InMemoryResultBackend();
    final registry = SimpleTaskRegistry()..register(_FlakyTask());
    final worker = Worker(broker: broker, registry: registry, backend: backend);
    await worker.start();

    final stem = Stem(broker: broker, registry: registry, backend: backend);

    final runner = PropertyTestRunner<int>(
      Gen.integer(min: 0, max: 5),
      (failures) async {
        final taskId = await stem.enqueue(
          _FlakyTask().name,
          args: {'failures': failures},
        );
        final result = await stem.waitForTask<String>(
          taskId,
          timeout: const Duration(seconds: 4),
        );

        if (failures <= _FlakyTask().options.maxRetries) {
          expect(result?.isSucceeded, isTrue);
          expect(result?.value, equals('ok'));
        } else {
          expect(result?.isFailed, isTrue);
        }
      },
      fastPropertyConfig,
    );

    await expectProperty(
      runner,
      description: 'retry semantics',
    );

    await worker.shutdown();
    await backend.close();
    await broker.close();
  });
}
