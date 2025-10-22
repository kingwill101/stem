import 'dart:async';

import 'package:test/test.dart';
import 'package:stem/stem.dart';

void main() {
  group('Signal', () {
    test('invokes handlers respecting priority', () async {
      final signal = Signal<String>(name: 'test');
      final calls = <String>[];
      signal.connect((payload, _) => calls.add('low:$payload'));
      signal.connect(
        (payload, _) => calls.add('high:$payload'),
        priority: 10,
      );

      await signal.emit('payload');

      expect(calls, equals(['high:payload', 'low:payload']));
    });

    test('supports once subscriptions', () async {
      final signal = Signal<int>(name: 'once');
      final values = <int>[];

      signal.connect((value, _) => values.add(value), once: true);

      await signal.emit(1);
      await signal.emit(2);

      expect(values, equals([1]));
    });

    test('applies filters', () async {
      final signal = Signal<int>(name: 'filter');
      final values = <int>[];

      signal.connect(
        (value, _) => values.add(value),
        filter: SignalFilter.where((value, _) => value.isEven),
      );

      await signal.emit(1);
      await signal.emit(2);

      expect(values, equals([2]));
    });

    test('reports handler errors', () async {
      Object? capturedError;
      StackTrace? capturedStack;

      final signal = Signal<void>(
        name: 'errors',
        config: SignalDispatchConfig(
          onError: (name, error, stack) {
            capturedError = error;
            capturedStack = stack;
          },
        ),
      );

      signal.connect((_, __) => throw StateError('boom'));

      await signal.emit(null);

      expect(capturedError, isA<StateError>());
      expect(capturedStack, isNotNull);
    });
  });

  group('StemSignals integration', () {
    test('enqueuing task emits publish signals', () async {
      StemSignals.configure(configuration: const StemSignalConfiguration());

      final broker = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );
      final backend = InMemoryResultBackend();
      final registry = SimpleTaskRegistry()..register(_SuccessTask());

      final before = Completer<String>();
      final after = Completer<String>();

      final subscriptions = <SignalSubscription>[
        StemSignals.beforeTaskPublish.connect((payload, _) {
          if (!before.isCompleted) {
            before.complete(payload.envelope.id);
          }
        }),
        StemSignals.afterTaskPublish.connect((payload, _) {
          if (!after.isCompleted) {
            after.complete(payload.taskId);
          }
        }),
      ];

      final stem = Stem(broker: broker, registry: registry, backend: backend);
      final taskId = await stem.enqueue('tasks.success');

      expect(await before.future, equals(taskId));
      expect(await after.future, equals(taskId));

      for (final sub in subscriptions) {
        sub.cancel();
      }
      broker.dispose();
    });
  });
}

class _SuccessTask implements TaskHandler<String> {
  @override
  String get name => 'tasks.success';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 1);

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<String> call(TaskContext context, Map<String, Object?> args) async {
    return 'ok';
  }
}
