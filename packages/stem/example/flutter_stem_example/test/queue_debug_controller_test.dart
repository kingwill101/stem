import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_stem_example/src/demo_config.dart';
import 'package:flutter_stem_example/src/demo_tasks.dart';
import 'package:flutter_stem_example/src/queue_debug_controller.dart';
import 'package:stem/memory.dart';
import 'package:stem/stem.dart';

class ObservedBroker extends InMemoryBroker {
  int inFlight = 0;
  @override
  Future<int> inflightCount(String queue) async => inFlight;
}

class GatedBackend extends InMemoryResultBackend {
  int reads = 0;
  Completer<TaskStatusPage>? gate;
  TaskStatusPage page = const TaskStatusPage(items: []);
  Object? failure;

  @override
  Future<TaskStatusPage> listTaskStatuses(TaskStatusListRequest request) async {
    expectSync(request.queue, queueName);
    reads++;
    if (failure case final error?) throw error;
    return gate == null ? page : await gate!.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GatedBackend backend;
  late ObservedBroker broker;
  late StemApp app;
  late QueueDebugController controller;

  setUp(() async {
    backend = GatedBackend();
    broker = ObservedBroker();
    app = await StemApp.create(
      module: demoModule,
      broker: StemBrokerFactory(
        create: () async => broker,
        dispose: (broker) => (broker as ObservedBroker).close(),
      ),
      backend: StemBackendFactory(
        create: () async => backend,
        dispose: (backend) => (backend as GatedBackend).close(),
      ),
      workerConfig: const StemWorkerConfig(concurrency: 1),
    );
    controller = QueueDebugController(
      app,
      queueName: queueName,
      reconciliationInterval: const Duration(milliseconds: 20),
    );
  });

  tearDown(() async {
    await controller.dispose();
    await app.close();
  });

  test('coalesces requests during a stale read into a terminal read', () async {
    final gate = backend.gate = Completer<TaskStatusPage>();
    final first = controller.refresh();
    final second = controller.refresh();
    final third = controller.refresh();
    expect(identical(first, second), isTrue);
    expect(identical(second, third), isTrue);
    final now = DateTime.now();
    backend.page = TaskStatusPage(
      items: [
        TaskStatusRecord(
          status: TaskStatus(
            id: 'completed',
            state: TaskState.succeeded,
            attempt: 1,
          ),
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
    backend.gate = null;
    gate.complete(const TaskStatusPage(items: []));
    await first;
    expect(backend.reads, 2);
    expect(controller.jobs.single.status.state, TaskState.succeeded);
  });

  test('retains a request delivered as the read finishes', () async {
    var notified = false;
    final refreshed = Completer<void>();
    final sub = controller.changes.listen((_) {
      if (notified) {
        refreshed.complete();
        return;
      }
      notified = true;
      unawaited(controller.refresh());
    });
    await controller.refresh();
    await refreshed.future;
    expect(backend.reads, 2);
    await sub.cancel();
  });

  test(
    'dispose waits for reads, suppresses notifications and rejects refresh',
    () async {
      final gate = backend.gate = Completer<TaskStatusPage>();
      var notifications = 0;
      final sub = controller.changes.listen((_) => notifications++);
      final reading = controller.refresh();
      var disposed = false;
      final closing = controller.dispose().then((_) => disposed = true);
      await Future<void>.delayed(Duration.zero);
      expect(disposed, isFalse);
      gate.complete(const TaskStatusPage(items: []));
      await reading;
      await closing;
      await controller.refresh();
      await controller.start();
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(backend.reads, 1);
      expect(notifications, 0);
      await sub.cancel();
    },
  );

  test(
    'start is idempotent and resume refreshes without starting the worker',
    () async {
      await controller.start();
      await controller.start();
      expect(backend.reads, 1);
      expect(controller.isRunning, isFalse);
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(backend.reads, 1);
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await controller.changes.first;
      expect(backend.reads, 2);
      expect(app.isStarted, isFalse);
    },
  );

  test('read failure is visible and a later refresh recovers', () async {
    backend.failure = StateError('read unavailable');
    await controller.start();
    expect(controller.observationError, isA<StateError>());
    backend.failure = null;
    await controller.refresh();
    expect(controller.observationError, isNull);
    expect(controller.updatedAt, isNotNull);
  });

  test('reconciliation stops idle, hidden and disposed', () async {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    final now = DateTime.now();
    backend.page = TaskStatusPage(
      items: [
        TaskStatusRecord(
          status: TaskStatus(
            id: 'pending',
            state: TaskState.running,
            attempt: 1,
          ),
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
    await controller.start();
    await controller.changes.first.timeout(const Duration(seconds: 2));
    expect(backend.reads, 2);
    controller.setVisible(false);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(backend.reads, 2);
    controller.setVisible(true);
    await controller.changes.first.timeout(const Duration(seconds: 2));
    expect(backend.reads, 3);
    backend.page = const TaskStatusPage(items: []);
    await controller.changes.first.timeout(const Duration(seconds: 2));
    expect(backend.reads, 4);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(backend.reads, 4, reason: 'No polling when the queue is idle.');
    backend.failure = StateError('cross-engine read failed');
    await controller.refresh();
    await controller.changes.first.timeout(const Duration(seconds: 2));
    expect(
      backend.reads,
      6,
      reason: 'Read failures keep reconciliation alive.',
    );
    await controller.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(backend.reads, 6);
  });

  test('completion before ACK is reconciled without another event', () async {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    broker.inFlight = 1;
    await controller.start();
    expect(controller.inflightCount, 1);
    broker.inFlight = 0;
    await controller.changes.first.timeout(const Duration(seconds: 2));
    expect(controller.inflightCount, 0);
    expect(backend.reads, 2);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(backend.reads, 2);
  });
}
