import 'dart:async';

import 'package:stem/memory.dart';
import 'package:stem/stem.dart';
import 'package:test/test.dart';

const _idle = Duration(milliseconds: 20);

Future<Object?> _isolatedWork(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async => 'done';

Future<StemApp> _createApp({
  required List<String> closed,
  Iterable<TaskHandler<Object?>> tasks = const [],
  StemWorkerConfig workerConfig = const StemWorkerConfig(
    concurrency: 1,
    lifecycle: WorkerLifecycleConfig(installSignalHandlers: false),
  ),
}) async {
  final app = await StemApp.create(
    tasks: tasks,
    broker: StemBrokerFactory(
      create: () async => InMemoryBroker(),
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
      },
    ),
    workerConfig: workerConfig,
  );
  addTearDown(app.shutdown);
  return app;
}

Future<WorkerRunOutcome> _run(StemApp app, {Future<void>? cancellation}) =>
    app.runUntilIdle(
      budget: const Duration(seconds: 5),
      shutdownReserve: Duration.zero,
      idleTimeout: _idle,
      cancellation: cancellation,
    );

void main() {
  test('startup ownership is visible before worker-init can reenter', () async {
    final app = await _createApp(closed: []);
    Future<void>? nestedStart;
    var initializations = 0;
    final subscription = StemSignals.workerInit.connect((_, _) async {
      initializations++;
      nestedStart = app.worker.start();
      await nestedStart;
      await app.start();
    });
    addTearDown(subscription.cancel);
    final first = app.worker.start();
    expect(app.worker.start(), same(first));
    await first.timeout(const Duration(seconds: 2));
    expect(nestedStart, isNotNull);
    expect(initializations, 1);
    await expectLater(_run(app), throwsStateError);
  });

  for (final bounded in [false, true]) {
    for (final stopApp in [false, true]) {
      test(
        'ready self-join is rejected (bounded=$bounded, app=$stopApp)',
        () async {
          final closed = <String>[];
          final app = await _createApp(closed: closed);
          Object? rejected;
          final subscription = StemSignals.workerReady.connect((_, _) async {
            try {
              await (stopApp ? app.shutdown() : app.worker.shutdown());
            } on Object catch (error) {
              rejected = error;
            }
          });
          addTearDown(subscription.cancel);
          if (bounded) {
            final outcome = await _run(app).timeout(const Duration(seconds: 2));
            expect(outcome.reason, WorkerRunStopReason.idle);
          } else {
            await app.start().timeout(const Duration(seconds: 2));
            expect(app.isStarted, isTrue);
            expect(closed, isEmpty);
            await app.shutdown();
          }
          expect(rejected, isA<StateError>());
          expect(closed, ['backend', 'broker']);
        },
      );
    }
  }

  for (final initializing in [true, false]) {
    test(
      'bounded shutdown joins child lifecycle hook (init=$initializing)',
      () async {
        final closed = <String>[];
        final app = await _createApp(
          closed: closed,
          tasks: [
            FunctionTaskHandler<String>(
              name: 'work',
              entrypoint: _isolatedWork,
            ),
          ],
        );
        final entered = Completer<void>();
        final release = Completer<void>();
        addTearDown(() {
          if (!release.isCompleted) release.complete();
        });
        final signal = initializing
            ? StemSignals.workerChildInit
            : StemSignals.workerChildShutdown;
        final subscription = signal.connect((_, _) async {
          if (!entered.isCompleted) entered.complete();
          await release.future;
          expect(closed, isEmpty);
        });
        addTearDown(subscription.cancel);
        await app.enqueue('work');
        var returned = false;
        final running = _run(app).then((outcome) {
          returned = true;
          return outcome;
        });
        await entered.future.timeout(const Duration(seconds: 2));
        await Future<void>.delayed(_idle * 3);
        expect(returned, isFalse);
        expect(closed, isEmpty);
        release.complete();
        final outcome = await running.timeout(const Duration(seconds: 2));
        expect(outcome.reason, WorkerRunStopReason.idle);
        expect(outcome.deliveriesProcessed, 1);
        expect(closed, ['backend', 'broker']);
      },
    );
  }

  test('late inline code cannot self-join after its timeout', () async {
    final closed = <String>[];
    final release = Completer<void>();
    Object? rejected;
    late final StemApp app;
    app = await _createApp(
      closed: closed,
      tasks: [
        FunctionTaskHandler<String>.inline(
          name: 'work',
          options: const TaskOptions(
            hardTimeLimit: Duration(milliseconds: 20),
          ),
          entrypoint: (context, args) async {
            await release.future;
            try {
              await app.shutdown();
            } on Object catch (error) {
              rejected = error;
            }
            return 'late';
          },
        ),
      ],
    );
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    final postrun = Completer<void>();
    final subscription = StemSignals.taskPostrun.connect((_, _) {
      postrun.complete();
    });
    addTearDown(subscription.cancel);
    await app.enqueue('work');
    final running = _run(app);
    await postrun.future.timeout(const Duration(seconds: 2));
    // The delivery scope has ended, but the underlying inline Future has not.
    await Future<void>.delayed(_idle * 3);
    expect(closed, isEmpty);
    release.complete();
    await running.timeout(const Duration(seconds: 2));
    expect(rejected, isA<StateError>());
    expect(closed, ['backend', 'broker']);
  });

  test('expired operation zones do not reject a later external join', () async {
    late Future<void> Function() later;
    late final StemApp app;
    app = await _createApp(
      closed: [],
      tasks: [
        FunctionTaskHandler<String>.inline(
          name: 'work',
          entrypoint: (context, args) async {
            later = Zone.current.bindCallback(app.shutdown);
            return 'done';
          },
        ),
      ],
    );
    await app.enqueue('work');
    await _run(app);
    await later();
  });

  test(
    'failed cancellation signal is reported without opening consumption',
    () async {
      final closed = <String>[];
      final app = await _createApp(closed: closed);
      final error = StateError('host cancellation failed');
      final outcome = await _run(
        app,
        cancellation: Future<void>.error(error),
      );
      expect(outcome.reason, WorkerRunStopReason.failed);
      expect(outcome.error, same(error));
      expect(outcome.deliveriesProcessed, 0);
      expect(closed, ['backend', 'broker']);
    },
  );

  test('broadcast rejection does not take ownership of a fresh app', () async {
    final closed = <String>[];
    final app = await _createApp(
      closed: closed,
      workerConfig: StemWorkerConfig(
        subscription: RoutingSubscription(
          queues: const [],
          broadcastChannels: const ['events'],
        ),
      ),
    );
    await expectLater(_run(app), throwsArgumentError);
    expect(closed, isEmpty);
    await app.shutdown();
    expect(closed, ['backend', 'broker']);
  });
}
