import 'dart:async';

import 'package:property_testing/property_testing.dart';
import 'package:stem/stem.dart';
import 'package:test/test.dart';

import '../../support/property_test_helpers.dart';

const _expiredMetaKey = 'stem.expired';

final _childDefinition = TaskDefinition<_ChildArgs, void>(
  name: 'tasks.child',
  encodeArgs: (args) => {'value': args.value},
);

void main() {
  group('TaskInvocationContext enqueue', () {
    test('enqueues from isolate entrypoint using builder', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      final childCompleted = Completer<String>();

      final registry = SimpleTaskRegistry()
        ..register(
          FunctionTaskHandler<void>.inline(
            name: _childDefinition.name,
            entrypoint: (context, args) async {
              childCompleted.complete(args['value']! as String);
              return null;
            },
          ),
        )
        ..register(_IsolateEnqueueTask());

      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-isolate-enqueue',
        concurrency: 1,
        prefetchMultiplier: 1,
      );

      await worker.start();
      final stem = Stem(broker: broker, registry: registry, backend: backend);
      await stem.enqueue('tasks.isolate.enqueue');

      final value = await childCompleted.future.timeout(
        const Duration(seconds: 3),
      );
      expect(value, equals('from-isolate'));

      await worker.shutdown();
      broker.dispose();
    });
  });

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

  group('link/linkError callbacks', () {
    test('enqueues link callback on success', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      final linked = Completer<void>();

      final linkDefinition = TaskDefinition<_ChildArgs, void>(
        name: 'tasks.linked',
        encodeArgs: (args) => {'value': args.value},
      );

      final registry = SimpleTaskRegistry()
        ..register(
          FunctionTaskHandler<void>.inline(
            name: 'tasks.primary.success',
            entrypoint: (context, args) async {
              return null;
            },
          ),
        )
        ..register(
          FunctionTaskHandler<void>.inline(
            name: linkDefinition.name,
            entrypoint: (context, args) async {
              linked.complete();
              return null;
            },
          ),
        );

      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-link-success',
        concurrency: 1,
        prefetchMultiplier: 1,
      );

      await worker.start();
      final stem = Stem(broker: broker, registry: registry, backend: backend);

      await stem.enqueue(
        'tasks.primary.success',
        enqueueOptions: TaskEnqueueOptions(
          link: [linkDefinition(const _ChildArgs('linked'))],
        ),
      );

      await linked.future.timeout(const Duration(seconds: 3));

      await worker.shutdown();
      broker.dispose();
    });

    test('enqueues linkError callback on failure', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      final linked = Completer<void>();

      final linkDefinition = TaskDefinition<_ChildArgs, void>(
        name: 'tasks.linked.error',
        encodeArgs: (args) => {'value': args.value},
      );

      final registry = SimpleTaskRegistry()
        ..register(
          FunctionTaskHandler<void>.inline(
            name: 'tasks.primary.fail',
            entrypoint: (context, args) async {
              throw StateError('fail');
            },
          ),
        )
        ..register(
          FunctionTaskHandler<void>.inline(
            name: linkDefinition.name,
            entrypoint: (context, args) async {
              linked.complete();
              return null;
            },
          ),
        );

      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-link-failure',
        concurrency: 1,
        prefetchMultiplier: 1,
      );

      await worker.start();
      final stem = Stem(broker: broker, registry: registry, backend: backend);

      await stem.enqueue(
        'tasks.primary.fail',
        enqueueOptions: TaskEnqueueOptions(
          linkError: [linkDefinition(const _ChildArgs('linked'))],
        ),
      );

      await linked.future.timeout(const Duration(seconds: 3));

      await worker.shutdown();
      broker.dispose();
    });
  });

  group('ignore_result', () {
    test('skips result payload persistence', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()
        ..register(
          FunctionTaskHandler<String>.inline(
            name: 'tasks.payload',
            entrypoint: (context, args) async => 'payload',
          ),
        );

      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-ignore',
        concurrency: 1,
        prefetchMultiplier: 1,
      );

      await worker.start();
      final stem = Stem(broker: broker, registry: registry, backend: backend);

      final taskId = await stem.enqueue(
        'tasks.payload',
        enqueueOptions: const TaskEnqueueOptions(ignoreResult: true),
      );

      await _waitFor(
        () async => (await backend.get(taskId))?.state == TaskState.succeeded,
      );

      final status = await backend.get(taskId);
      expect(status?.state, equals(TaskState.succeeded));
      expect(status?.payload, isNull);

      await worker.shutdown();
      broker.dispose();
    });
  });

  group('expires', () {
    test('does not execute expired task', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      var executed = false;
      final registry = SimpleTaskRegistry()
        ..register(
          FunctionTaskHandler<void>.inline(
            name: 'tasks.expiring',
            entrypoint: (context, args) async {
              executed = true;
              return null;
            },
          ),
        );

      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-expired',
        concurrency: 1,
        prefetchMultiplier: 1,
      );

      await worker.start();
      final stem = Stem(broker: broker, registry: registry, backend: backend);

      final taskId = await stem.enqueue(
        'tasks.expiring',
        enqueueOptions: TaskEnqueueOptions(
          expires: DateTime.now().subtract(const Duration(seconds: 1)),
        ),
      );

      await _waitFor(
        () async => (await backend.get(taskId))?.state == TaskState.cancelled,
      );

      final status = await backend.get(taskId);
      expect(status?.state, equals(TaskState.cancelled));
      expect(status?.meta[_expiredMetaKey], isTrue);
      expect(executed, isFalse);

      await worker.shutdown();
      broker.dispose();
    });
  });

  group('taskId overwrite', () {
    test('overwrites existing task result state', () async {
      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 10),
        claimInterval: const Duration(milliseconds: 40),
      );
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()
        ..register(
          FunctionTaskHandler<int>.inline(
            name: 'tasks.echo',
            entrypoint: (context, args) async {
              return (args['value'] as int?) ?? 0;
            },
          ),
        );

      final worker = Worker(
        broker: broker,
        registry: registry,
        backend: backend,
        consumerName: 'worker-overwrite',
        concurrency: 1,
        prefetchMultiplier: 1,
      );

      await worker.start();
      final stem = Stem(broker: broker, registry: registry, backend: backend);

      const taskId = 'fixed-task-id';
      await stem.enqueue(
        'tasks.echo',
        args: const {'value': 1},
        enqueueOptions: const TaskEnqueueOptions(taskId: taskId),
      );

      await _waitFor(
        () async => (await backend.get(taskId))?.payload == 1,
      );

      await stem.enqueue(
        'tasks.echo',
        args: const {'value': 2},
        enqueueOptions: const TaskEnqueueOptions(taskId: taskId),
      );

      await _waitFor(
        () async => (await backend.get(taskId))?.payload == 2,
      );

      final status = await backend.get(taskId);
      expect(status?.payload, equals(2));

      await worker.shutdown();
      broker.dispose();
    });
  });
}

class _EchoTask extends TaskHandler<Map<String, Object?>> {
  @override
  String get name => 'property.echo';

  @override
  TaskOptions get options => const TaskOptions();

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

Future<void> _waitFor(
  FutureOr<bool> Function() predicate, {
  Duration timeout = const Duration(seconds: 3),
  Duration pollInterval = const Duration(milliseconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final ready = await predicate();
    if (ready) return;
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition not met within $timeout');
    }
    await Future<void>.delayed(pollInterval);
  }
}

class _ChildArgs {
  const _ChildArgs(this.value);
  final String value;
}

class _IsolateEnqueueTask implements TaskHandler<void> {
  @override
  String get name => 'tasks.isolate.enqueue';

  @override
  TaskOptions get options => const TaskOptions();

  @override
  TaskMetadata get metadata => const TaskMetadata();

  @override
  TaskEntrypoint? get isolateEntrypoint => _isolateEnqueueEntrypoint;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {}
}

FutureOr<Object?> _isolateEnqueueEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  final builder = context.enqueueBuilder(
    definition: _childDefinition,
    args: const _ChildArgs('from-isolate'),
  );
  await builder.enqueueWith(context);
  return null;
}
