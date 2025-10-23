import 'dart:async';

import 'package:test/test.dart';
import 'package:stem/stem.dart';

void main() {
  group('Signal', () {
    test('invokes handlers respecting priority', () async {
      final signal = Signal<String>(name: 'test');
      final calls = <String>[];
      signal.connect((payload, _) => calls.add('low:$payload'));
      signal.connect((payload, _) => calls.add('high:$payload'), priority: 10);

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

    test('per-signal configuration disables selected handlers', () async {
      StemSignals.configure(
        configuration: const StemSignalConfiguration(
          enabledSignals: {StemSignals.taskPrerunName: false},
        ),
      );
      addTearDown(() {
        StemSignals.configure(configuration: const StemSignalConfiguration());
      });

      var invoked = false;
      StemSignals.taskPrerun.connect((payload, _) {
        invoked = true;
      });

      final envelope = Envelope(name: 'tasks.disabled', args: const {});
      final worker = const WorkerInfo(
        id: 'worker',
        queues: ['default'],
        broadcasts: [],
      );
      final context = TaskContext(
        id: envelope.id,
        attempt: envelope.attempt,
        headers: envelope.headers,
        meta: envelope.meta,
        heartbeat: () {},
        extendLease: (_) async {},
        progress: (_, {data}) async {},
      );

      await StemSignals.taskPrerun.emit(
        TaskPrerunPayload(envelope: envelope, worker: worker, context: context),
      );

      expect(invoked, isFalse);
    });
  });

  group('SignalMiddleware', () {
    test('coordinator forwards publish lifecycle', () async {
      StemSignals.configure(configuration: const StemSignalConfiguration());
      addTearDown(() {
        StemSignals.configure(configuration: const StemSignalConfiguration());
      });

      final middleware = SignalMiddleware.coordinator();
      final envelope = Envelope(name: 'tasks.demo', args: const {});
      final calls = <String>[];
      final subscriptions = <SignalSubscription>[
        StemSignals.beforeTaskPublish.connect((payload, _) {
          calls.add('before');
        }),
        StemSignals.afterTaskPublish.connect((payload, _) {
          calls.add('after');
        }),
      ];

      await middleware.onEnqueue(envelope, () async {});

      expect(calls, equals(['before', 'after']));
      for (final sub in subscriptions) {
        sub.cancel();
      }
    });

    test('worker forwards consume, prerun, and failure signals', () async {
      StemSignals.configure(configuration: const StemSignalConfiguration());
      addTearDown(() {
        StemSignals.configure(configuration: const StemSignalConfiguration());
      });

      const workerInfo = WorkerInfo(
        id: 'worker-1',
        queues: ['default'],
        broadcasts: [],
      );
      final middleware = SignalMiddleware.worker(workerInfo: () => workerInfo);
      final envelope = Envelope(name: 'tasks.test', args: const {});
      final delivery = Delivery(
        envelope: envelope,
        receipt: 'receipt-1',
        leaseExpiresAt: DateTime.now().add(const Duration(minutes: 1)),
      );

      final received = Completer<void>();
      final prerun = Completer<void>();
      final failed = Completer<void>();

      final subscriptions = <SignalSubscription>[
        StemSignals.taskReceived.connect((payload, _) {
          if (!received.isCompleted) {
            received.complete();
          }
        }),
        StemSignals.taskPrerun.connect((payload, _) {
          if (!prerun.isCompleted) {
            prerun.complete();
          }
        }),
        StemSignals.taskFailed.connect((payload, _) {
          if (!failed.isCompleted) {
            failed.complete();
          }
        }),
      ];

      await middleware.onConsume(delivery, () async {});
      final context = TaskContext(
        id: envelope.id,
        attempt: envelope.attempt,
        headers: envelope.headers,
        meta: envelope.meta,
        heartbeat: () {},
        extendLease: (_) async {},
        progress: (_, {data}) async {},
      );

      try {
        await middleware.onExecute(context, () async {
          throw StateError('boom');
        });
      } catch (_) {}
      await middleware.onError(context, StateError('boom'), StackTrace.current);

      expect(received.isCompleted, isTrue);
      expect(prerun.isCompleted, isTrue);
      expect(failed.isCompleted, isTrue);

      for (final sub in subscriptions) {
        sub.cancel();
      }
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
