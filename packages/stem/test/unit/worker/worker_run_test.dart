import 'dart:async';

import 'package:stem/memory.dart';
import 'package:stem/stem.dart';
import 'package:test/test.dart';

const _idle = Duration(milliseconds: 20);
const _budget = Duration(seconds: 5);

void main() {
  test('idle uses subscription quiescence, not queue count polling', () async {
    final fixture = await _Fixture.create();
    final outcome = await fixture.run();
    expect(outcome.reason, WorkerRunStopReason.idle);
    expect(outcome.deliveriesProcessed, 0);
    expect(fixture.broker.subscriptions, 1);
    expect(fixture.broker.cancelled.isCompleted, isTrue);
    expect(fixture.app.isStarted, isFalse);
  });

  test('drains multiple deliveries across acknowledgements', () async {
    var calls = 0;
    final fixture = await _Fixture.create(
      task: _Task(() async => ++calls),
    );
    final ids = <String>[];
    for (var i = 0; i < 8; i++) {
      ids.add(await fixture.app.enqueue('work'));
    }
    final outcome = await fixture.run();
    expect(outcome.reason, WorkerRunStopReason.idle);
    expect(outcome.deliveriesProcessed, 8);
    expect(calls, 8);
    expect(fixture.broker.acks, 8);
    for (final id in ids) {
      expect((await fixture.backend.get(id))?.state, TaskState.succeeded);
    }
  });

  test('leaves future ETA work for another invocation', () async {
    final fixture = await _Fixture.create();
    final id = await fixture.app.enqueue(
      'work',
      notBefore: DateTime.now().add(const Duration(hours: 1)),
    );
    final outcome = await fixture.run();
    expect(outcome.reason, WorkerRunStopReason.idle);
    expect(outcome.deliveriesProcessed, 0);
    expect(fixture.broker.acks, 0);
    expect((await fixture.backend.get(id))?.state, TaskState.queued);
  });

  test('already-cancelled invocation opens no subscription', () async {
    final fixture = await _Fixture.create();
    await fixture.app.enqueue('work');
    final outcome = await fixture.run(cancellation: Future<void>.value());
    expect(outcome.reason, WorkerRunStopReason.cancelled);
    expect(outcome.deliveriesProcessed, 0);
    expect(fixture.broker.subscriptions, 0);
    expect(await fixture.broker.readyCount(), 1);
  });

  test(
    'delivery racing with stop is requeued and joined, not executed',
    () async {
      final broker = _RacingBroker();
      var calls = 0;
      final fixture = await _Fixture.create(
        broker: broker,
        owned: true,
        task: _Task(() async => calls++),
      );
      addTearDown(() {
        if (!broker.nackRelease.isCompleted) broker.nackRelease.complete();
      });
      final ready = Completer<void>();
      final subscription = StemSignals.workerReady.connect((_, _) {
        ready.complete();
      });
      addTearDown(subscription.cancel);
      final running = fixture.run();
      await ready.future;
      final shutdown = fixture.app.worker.shutdown();
      broker.deliver(
        Delivery(
          envelope: Envelope(name: 'work', args: const {}),
          receipt: 'late-receipt',
          leaseExpiresAt: null,
        ),
      );
      expect(broker.rejected, [('late-receipt', true)]);
      expect(calls, 0);
      expect(fixture.closed, isEmpty);
      broker.nackRelease.complete();
      final outcome = await running;
      await shutdown;
      expect(outcome.reason, WorkerRunStopReason.cancelled);
      expect(outcome.deliveriesProcessed, 0);
      expect(broker.acks, 0);
      expect(fixture.closed, ['backend', 'broker']);
    },
  );

  test(
    'concurrent shutdown joins an outstanding subscription cancellation',
    () async {
      final broker = _RacingBroker()..cancelRelease = Completer<void>();
      final fixture = await _Fixture.create(broker: broker, owned: true);
      addTearDown(() {
        if (!broker.cancelRelease!.isCompleted) {
          broker.cancelRelease!.complete();
        }
      });
      final running = fixture.run();
      await broker.cancelEntered.future;
      final shutdown = fixture.app.shutdown();
      await Future<void>.delayed(Duration.zero);
      expect(fixture.closed, isEmpty);
      broker.cancelRelease!.complete();
      expect((await running).reason, WorkerRunStopReason.idle);
      await shutdown;
      expect(fixture.closed, ['backend', 'broker']);
    },
  );

  test(
    'cancellation stops consumption while worker-ready is still pending',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final subscription = StemSignals.workerReady.connect((_, _) async {
        entered.complete();
        await release.future;
      });
      addTearDown(subscription.cancel);
      final fixture = await _Fixture.create(owned: true);
      final cancellation = Completer<void>();
      final running = fixture.run(cancellation: cancellation.future);
      await entered.future;
      cancellation.complete();
      // This must not depend on workerReady completing.
      await fixture.broker.cancelled.future;
      expect(fixture.closed, isEmpty);
      await fixture.app.enqueue('work');
      release.complete();
      final outcome = await running;
      expect(outcome.reason, WorkerRunStopReason.cancelled);
      expect(outcome.deliveriesProcessed, 0);
      expect(fixture.remainingAtClose, 1);
    },
  );

  for (final stop in ['budget', 'cancel', 'app shutdown', 'worker shutdown']) {
    test('$stop stops admission and drains the running handler', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final cancellation = Completer<void>();
      var calls = 0;
      late final _Fixture fixture;
      fixture = await _Fixture.create(
        owned: true,
        task: _Task(() async {
          calls++;
          entered.complete();
          await release.future;
          expect(fixture.closed, isEmpty);
          return 'done';
        }),
      );
      await fixture.app.enqueue('work');
      await fixture.app.enqueue('work');
      var completed = false;
      final running = fixture
          .run(
            budget: stop == 'budget'
                ? const Duration(milliseconds: 150)
                : _budget,
            cancellation: cancellation.future,
          )
          .then((result) {
            completed = true;
            return result;
          });
      await entered.future;
      Future<void>? shutdown;
      if (stop == 'cancel') cancellation.complete();
      if (stop == 'app shutdown') shutdown = fixture.app.shutdown();
      if (stop == 'worker shutdown') {
        shutdown = fixture.app.worker.shutdown();
      }
      await fixture.broker.cancelled.future;
      expect(completed, isFalse);
      expect(fixture.closed, isEmpty);
      expect(calls, 1);
      release.complete();
      final outcome = await running;
      await shutdown;
      expect(
        outcome.reason,
        stop == 'budget'
            ? WorkerRunStopReason.budgetExceeded
            : WorkerRunStopReason.cancelled,
      );
      expect(outcome.deliveriesProcessed, 1);
      expect(calls, 1);
      expect(fixture.closed, ['backend', 'broker']);
      expect(fixture.broker.acks, 1);
      // Disposal records the pending work before closing the owned broker.
      expect(fixture.remainingAtClose, 1);
    });
  }

  test(
    'result persistence is not drain: gated ACK keeps resources open',
    () async {
      final broker = _Broker()..gateAck = Completer<void>();
      final fixture = await _Fixture.create(broker: broker, owned: true);
      final id = await fixture.app.enqueue('work');
      final cancellation = Completer<void>();
      final running = fixture.run(cancellation: cancellation.future);
      await broker.ackEntered.future;
      expect((await fixture.backend.get(id))?.state, TaskState.succeeded);
      cancellation.complete();
      await broker.cancelled.future;
      expect(fixture.closed, isEmpty);
      expect(broker.acks, 0);
      broker.gateAck!.complete();
      expect((await running).reason, WorkerRunStopReason.cancelled);
      expect(broker.acks, 1);
      expect(fixture.closed, ['backend', 'broker']);
    },
  );

  test(
    'postrun hook is included after acknowledgement and active release',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final subscription = StemSignals.taskPostrun.connect((_, _) async {
        entered.complete();
        await release.future;
      });
      addTearDown(subscription.cancel);
      final fixture = await _Fixture.create(owned: true);
      await fixture.app.enqueue('work');
      final cancellation = Completer<void>();
      final running = fixture.run(cancellation: cancellation.future);
      await entered.future;
      cancellation.complete();
      await fixture.broker.cancelled.future;
      expect(fixture.broker.acks, 1);
      expect(fixture.closed, isEmpty);
      release.complete();
      await running;
      expect(fixture.closed, ['backend', 'broker']);
    },
  );

  test(
    'timed-out inline Future must quiesce before resource disposal',
    () async {
      final release = Completer<void>();
      final fixture = await _Fixture.create(
        owned: true,
        task: _Task(
          () async {
            await release.future;
            return 'late';
          },
          options: const TaskOptions(
            hardTimeLimit: Duration(milliseconds: 20),
          ),
        ),
      );
      final id = await fixture.app.enqueue('work');
      final running = fixture.run();
      // The normal execution timeout has persisted failure and acknowledged,
      // and the runner has stopped subscription admission. Inline code remains.
      await fixture.broker.cancelled.future;
      expect((await fixture.backend.get(id))?.state, TaskState.failed);
      expect(fixture.closed, isEmpty);
      release.complete();
      await running;
      expect(fixture.closed, ['backend', 'broker']);
    },
  );

  test('task failure is not invocation infrastructure failure', () async {
    final fixture = await _Fixture.create(
      task: _Task(
        () async => throw StateError('task failed'),
      ),
    );
    final id = await fixture.app.enqueue('work');
    final outcome = await fixture.run();
    expect(outcome.reason, WorkerRunStopReason.idle);
    expect(outcome.error, isNull);
    expect((await fixture.backend.get(id))?.state, TaskState.failed);
  });

  test('in-flight lease renewal completes before owned stores close', () async {
    final release = Completer<void>();
    final broker = _Broker()..gateLease = Completer<void>();
    final fixture = await _Fixture.create(
      broker: broker,
      owned: true,
      task: _Task(() async {
        await release.future;
        return 'done';
      }),
    );
    await fixture.app.enqueue(
      'work',
      options: const TaskOptions(
        visibilityTimeout: Duration(milliseconds: 100),
      ),
    );
    final cancellation = Completer<void>();
    final running = fixture.run(cancellation: cancellation.future);
    await broker.leaseEntered.future;
    cancellation.complete();
    await broker.cancelled.future;
    release.complete();
    await broker.ackEntered.future;
    // Drain can finish the delivery while a timer's broker operation is still
    // in flight. Timer cancellation alone is not sufficient for disposal.
    await Future<void>.delayed(_idle);
    expect(fixture.closed, isEmpty);
    broker.gateLease!.complete();
    await running;
    expect(fixture.closed, ['backend', 'broker']);
  });

  test(
    'pre-execution middleware is drained even before handler tracking',
    () async {
      final middleware = _ConsumeGate();
      final fixture = await _Fixture.create(
        owned: true,
        middleware: [middleware],
      );
      await fixture.app.enqueue('work');
      final cancellation = Completer<void>();
      final running = fixture.run(cancellation: cancellation.future);
      await middleware.entered.future;
      cancellation.complete();
      await fixture.broker.cancelled.future;
      expect(fixture.closed, isEmpty);
      middleware.release.complete();
      expect((await running).deliveriesProcessed, 1);
      expect(fixture.broker.acks, 1);
      expect(fixture.closed, ['backend', 'broker']);
    },
  );

  test('cleanup errors throw after all app disposers are attempted', () async {
    final closed = <String>[];
    final error = StateError('backend close failed');
    final app = await StemApp.create(
      broker: StemBrokerFactory(
        create: () async => _Broker(),
        dispose: (broker) async {
          closed.add('broker');
          await broker.close();
        },
      ),
      backend: StemBackendFactory(
        create: () async => InMemoryResultBackend(),
        dispose: (backend) async {
          closed.add('backend');
          await backend.close();
          throw error;
        },
      ),
    );
    await expectLater(
      app.runUntilIdle(
        budget: _budget,
        shutdownReserve: Duration.zero,
        idleTimeout: _idle,
      ),
      throwsA(same(error)),
    );
    expect(closed, ['backend', 'broker']);
    await expectLater(app.shutdown(), throwsA(same(error)));
    expect(closed, ['backend', 'broker']);
  });

  test(
    'ACK failure reports failed without overwriting durable success',
    () async {
      final error = StateError('ack unavailable');
      final broker = _Broker()..ackError = error;
      final fixture = await _Fixture.create(broker: broker);
      final id = await fixture.app.enqueue('work');
      final outcome = await fixture.run();
      expect(outcome.reason, WorkerRunStopReason.failed);
      expect(outcome.error, same(error));
      expect(outcome.stackTrace, isNotNull);
      expect((await fixture.backend.get(id))?.state, TaskState.succeeded);
      expect(broker.acks, 0);
    },
  );

  for (final synchronous in [true, false]) {
    test(
      'consume ${synchronous ? 'startup' : 'stream'} error is structured',
      () async {
        final error = StateError('transport failed');
        final fixture = await _Fixture.create(
          broker: _Broker()
            ..consumeError = error
            ..synchronousError = synchronous,
          owned: true,
        );
        final outcome = await fixture.run();
        expect(outcome.reason, WorkerRunStopReason.failed);
        expect(outcome.error, same(error));
        expect(fixture.closed, ['backend', 'broker']);
      },
    );
  }

  test('rejects invalid budgets and reuse without taking ownership', () async {
    final fixture = await _Fixture.create();
    await expectLater(
      fixture.app.runUntilIdle(budget: const Duration(seconds: 1)),
      throwsArgumentError,
    );
    expect(fixture.broker.subscriptions, 0);
    await fixture.run();
    await expectLater(fixture.run(), throwsStateError);
    await expectLater(fixture.app.start(), throwsStateError);
    await expectLater(fixture.app.worker.start(), throwsStateError);
  });

  test('concurrent run is rejected while shutdown joins execution', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final fixture = await _Fixture.create(
      task: _Task(() async {
        entered.complete();
        await release.future;
        return null;
      }),
    );
    await fixture.app.enqueue('work');
    final running = fixture.run();
    await entered.future;
    await expectLater(fixture.run(), throwsStateError);
    await expectLater(fixture.app.start(), throwsStateError);
    final first = fixture.app.shutdown();
    expect(fixture.app.shutdown(), same(first));
    release.complete();
    await first;
    expect((await running).reason, WorkerRunStopReason.cancelled);
  });
}

int _namespace = 0;

class _Fixture {
  _Fixture(this.broker, this.backend);

  final _Broker broker;
  final InMemoryResultBackend backend;
  late final StemApp app;
  final List<String> closed = [];
  int? remainingAtClose;

  static Future<_Fixture> create({
    _Task? task,
    _Broker? broker,
    bool owned = false,
    List<Middleware> middleware = const [],
  }) async {
    final fixture = _Fixture(
      broker ?? _Broker(),
      InMemoryResultBackend(),
    );
    fixture.app = await StemApp.create(
      tasks: [task ?? _Task(() async => 'done')],
      middleware: middleware,
      broker: StemBrokerFactory(
        create: () async => fixture.broker,
        dispose: owned
            ? (value) async {
                fixture.remainingAtClose = await fixture.broker.readyCount();
                fixture.closed.add('broker');
                await value.close();
              }
            : null,
      ),
      backend: StemBackendFactory(
        create: () async => fixture.backend,
        dispose: owned
            ? (value) async {
                fixture.closed.add('backend');
                await value.close();
              }
            : null,
      ),
      workerConfig: const StemWorkerConfig(
        concurrency: 1,
        lifecycle: WorkerLifecycleConfig(installSignalHandlers: false),
      ),
    );
    addTearDown(() async {
      await fixture.app.shutdown();
      if (!owned) {
        await fixture.backend.close();
        await fixture.broker.close();
      }
    });
    return fixture;
  }

  Future<WorkerRunOutcome> run({
    Duration budget = _budget,
    Future<void>? cancellation,
  }) => app.runUntilIdle(
    budget: budget,
    shutdownReserve: Duration.zero,
    idleTimeout: _idle,
    cancellation: cancellation,
  );
}

class _Task extends TaskHandler<Object?> {
  _Task(this.execute, {this.options = const TaskOptions()});

  final Future<Object?> Function() execute;
  @override
  final TaskOptions options;
  @override
  String get name => 'work';
  @override
  TaskMetadata get metadata => const TaskMetadata();
  @override
  Future<Object?> call(TaskContext context, Map<String, Object?> args) =>
      execute();
}

class _Broker extends InMemoryBroker {
  _Broker() : super(namespace: 'bounded-test-${_namespace++}');

  int subscriptions = 0;
  int acks = 0;
  final Completer<void> cancelled = Completer<void>();
  final Completer<void> ackEntered = Completer<void>();
  final Completer<void> leaseEntered = Completer<void>();
  Completer<void>? gateAck;
  Completer<void>? gateLease;
  StateError? ackError;
  StateError? consumeError;
  bool synchronousError = false;

  @override
  Future<int?> pendingCount(String queue) =>
      throw StateError('runner must not use pendingCount');

  Future<int?> readyCount() => super.pendingCount('default');

  @override
  Stream<Delivery> consume(
    RoutingSubscription subscription, {
    int prefetch = 1,
    String? consumerGroup,
    String? consumerName,
  }) {
    subscriptions++;
    expect(prefetch, 1);
    if (synchronousError) throw consumeError!;
    return _consume(subscription, prefetch, consumerName);
  }

  Stream<Delivery> _consume(
    RoutingSubscription subscription,
    int prefetch,
    String? consumerName,
  ) async* {
    try {
      if (consumeError != null) throw consumeError!;
      yield* super.consume(
        subscription,
        prefetch: prefetch,
        consumerName: consumerName,
      );
    } finally {
      if (!cancelled.isCompleted) cancelled.complete();
    }
  }

  @override
  Future<void> ack(Delivery delivery) async {
    if (!ackEntered.isCompleted) ackEntered.complete();
    await gateAck?.future;
    if (ackError != null) throw ackError!;
    await super.ack(delivery);
    acks++;
  }

  @override
  Future<void> extendLease(Delivery delivery, Duration duration) async {
    if (!leaseEntered.isCompleted) leaseEntered.complete();
    await gateLease?.future;
    await super.extendLease(delivery, duration);
  }
}

class _ConsumeGate implements Middleware {
  final Completer<void> entered = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<void> onConsume(
    Delivery delivery,
    Future<void> Function() next,
  ) async {
    entered.complete();
    await release.future;
    await next();
  }

  @override
  Future<void> onEnqueue(Envelope envelope, Future<void> Function() next) =>
      next();

  @override
  Future<void> onExecute(TaskContext context, Future<void> Function() next) =>
      next();

  @override
  Future<void> onError(
    TaskContext context,
    Object error,
    StackTrace stack,
  ) async {}
}

/// A synchronous delivery can reach the worker after stop is requested but
/// before the subscription-cancellation microtask has run.
class _RacingBroker extends _Broker {
  StreamController<Delivery>? _controller;
  final rejected = <(String, bool)>[];
  final nackRelease = Completer<void>();
  final cancelEntered = Completer<void>();
  Completer<void>? cancelRelease;

  @override
  Stream<Delivery> consume(
    RoutingSubscription subscription, {
    int prefetch = 1,
    String? consumerGroup,
    String? consumerName,
  }) {
    subscriptions++;
    _controller = StreamController<Delivery>(
      sync: true,
      onCancel: () async {
        cancelEntered.complete();
        await cancelRelease?.future;
        cancelled.complete();
      },
    );
    return _controller!.stream;
  }

  void deliver(Delivery delivery) => _controller!.add(delivery);

  @override
  Future<void> nack(Delivery delivery, {bool requeue = true}) async {
    rejected.add((delivery.receipt, requeue));
    await nackRelease.future;
  }

  @override
  Future<void> close() async {
    await _controller?.close();
    await super.close();
  }
}
