import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_stem_example/src/demo_config.dart';
import 'package:flutter_stem_example/src/demo_workflows.dart';
import 'package:flutter_stem_example/src/workflow_workbench_controller.dart';
import 'package:stem/stem.dart' show FunctionTaskHandler;
import 'package:stem_flutter_sqlite/stem_flutter_sqlite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late StemFlutterStorageLayout layout;
  final sessions = <_Session>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('stem-workbench-');
    layout = await StemFlutterStorageLayout.forRoot(directory);
  });
  tearDown(() async {
    for (final session in sessions.reversed) {
      await session.close();
    }
    sessions.clear();
    await directory.delete(recursive: true);
  });

  Future<_Session> open() async {
    final app = await StemFlutterSqlite.createApp(
      layout: layout,
      workerConfig: const StemWorkerConfig(queue: queueName, concurrency: 1),
      storage: const StemFlutterSqliteConfig(
        pollInterval: Duration(milliseconds: 10),
      ),
    );
    final workflows = await attachDemoWorkflows(app, layout: layout);
    final session = _Session(app, workflows);
    sessions.add(session);
    return session;
  }

  test('cancelling a run does not resume native wakeups', () async {
    final workflows = await StemWorkflowApp.inMemory(
      scripts: createDemoWorkflowScripts(),
      workerConfig: const StemWorkerConfig(queue: queueName),
    );
    var wakeups = 0;
    final controller = WorkflowWorkbenchController(
      workflows,
      requestWakeup: () async => wakeups++,
    );
    try {
      final ids = await controller.launch(WorkbenchWorkflowKind.approval);
      expect(wakeups, 1);
      await controller.cancel(ids.single);
      expect(wakeups, 1);
      expect(
        (await workflows.store.get(ids.single))!.status,
        WorkflowStatus.cancelled,
      );
    } finally {
      await controller.dispose();
      await workflows.close();
    }
  });

  test(
    'attachment rejects an incompatible core queue without owning it',
    () async {
      final app = await StemApp.inMemory();
      try {
        await expectLater(
          attachDemoWorkflows(app, layout: layout),
          throwsStateError,
        );
        expect(app.isStarted, isFalse);
      } finally {
        await app.close();
      }
    },
  );

  test(
    'independent producer launches complete in a fresh SQLite callback',
    () async {
      final producer = await open();
      final ids = [
        ...await producer.controller.launch(
          WorkbenchWorkflowKind.report,
          count: 3,
        ),
        ...await producer.controller.launch(
          WorkbenchWorkflowKind.report,
          count: 2,
        ),
      ];
      expect(ids.toSet(), hasLength(5));
      expect(producer.workflows.isRuntimeStarted, isFalse);
      expect(producer.app.isStarted, isFalse);
      expect(producer.workflows.ownsStemApp, isFalse);
      await expectLater(
        producer.controller.launch(WorkbenchWorkflowKind.report, count: 6),
        throwsRangeError,
      );
      await expectLater(
        producer.controller.launch(WorkbenchWorkflowKind.report, count: 0),
        throwsRangeError,
      );
      await producer.close();

      final callback = await open();
      await callback.drain();
      for (final id in ids) {
        final detail = (await callback.workflows.viewRunDetail(id))!;
        expect(detail.run.status, WorkflowStatus.completed);
        expect(detail.run.result, {'rows': 3, 'total': 35});
        expect(
          detail.checkpoints.map((step) => step.checkpointName),
          unorderedEquals(['collect', 'total', 'publish']),
        );
      }
      await callback.close();
      final observer = await open();
      expect((await observer.workflows.listRunViews()), hasLength(5));
      expect((await observer.workflows.viewRun(ids.first))!.result, {
        'rows': 3,
        'total': 35,
      });
    },
  );

  test('a due sleep stays discoverable while bounded work drains', () async {
    final callback = await open();
    final entered = Completer<void>();
    final release = Completer<void>();
    callback.app.register(
      FunctionTaskHandler<void>.inline(
        name: 'test.hold',
        options: const TaskOptions(queue: queueName),
        entrypoint: (_, _) async {
          entered.complete();
          await release.future;
          return null;
        },
      ),
    );
    final id = await callback.workflows.runtime.startWorkflow(
      WorkbenchWorkflowKind.sleep.descriptor.name,
      params: {'delayMs': 100},
    );
    await callback.app.enqueue('test.hold');
    final running = callback.drain();
    try {
      await entered.future.timeout(const Duration(seconds: 3));
      final due = (await earliestWorkflowWakeAt(callback.workflows))!;
      // Cross the regular runtime's 500ms tick while another delivery is held.
      // Bounded setup must have stopped polling before worker admission.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(due.isBefore(DateTime.now()), isTrue);
      expect(
        (await callback.workflows.viewRun(id))!.status,
        WorkflowStatus.suspended,
      );
      expect(await earliestWorkflowWakeAt(callback.workflows), due);
    } finally {
      if (!release.isCompleted) release.complete();
      await running;
    }
    expect(await earliestWorkflowWakeAt(callback.workflows), isNotNull);
    await callback.close();
    final next = await open();
    await next.drain();
    expect(
      (await next.workflows.viewRun(id))!.status,
      WorkflowStatus.completed,
    );
  });

  test(
    'sleep outlives one bounded invocation and replays saved checkpoints',
    () async {
      final producer = await open();
      final id = await producer.workflows.runtime.startWorkflow(
        WorkbenchWorkflowKind.sleep.descriptor.name,
        params: {'delayMs': 1500},
      );
      await producer.close();

      final first = await open();
      await first.drain();
      final waiting = (await first.workflows.viewRunDetail(id))!;
      expect(waiting.run.status, WorkflowStatus.suspended);
      expect(waiting.checkpoints.map((step) => step.checkpointName), [
        'prepare',
      ]);
      final checkpoint = waiting.checkpoints.single;
      final wakeAt = (await earliestWorkflowWakeAt(first.workflows))!;
      final suspended = (await first.workflows.store.get(id))!;
      expect(suspended.suspensionData?['payload'], isTrue);
      await first.close();
      final remaining = wakeAt.difference(DateTime.now());
      if (remaining > Duration.zero) {
        await Future<void>.delayed(
          remaining + const Duration(milliseconds: 30),
        );
      }

      final second = await open();
      // Runtime startup must resume overdue persisted sleepers before a short
      // idle callback exits. No facade.start() or alternate consume loop.
      final restored = (await second.workflows.store.get(id))!;
      expect(restored.resumeAt, wakeAt);
      expect(restored.suspensionData?['payload'], isTrue);
      expect(restored.resumeAt!.isAfter(DateTime.now()), isFalse);
      await second.drain();
      final completed = (await second.workflows.viewRunDetail(id))!;
      expect(completed.run.status, WorkflowStatus.completed);
      expect(
        completed.checkpoints.map((step) => step.checkpointName),
        unorderedEquals(['prepare', 'sleep', 'finish']),
      );
      final replayed = completed.checkpoints.singleWhere(
        (step) => step.checkpointName == 'prepare',
      );
      expect(replayed.value, checkpoint.value);
      expect(replayed.completedAt, checkpoint.completedAt);
      expect(
        (completed.run.result as Map)['preparedAt'],
        (checkpoint.value as Map)['preparedAt'],
      );
      expect(await earliestWorkflowWakeAt(second.workflows), isNull);
    },
  );

  test(
    'approval targets only its run across restart and cancellation persists',
    () async {
      final producer = await open();
      final ids = await producer.controller.launch(
        WorkbenchWorkflowKind.approval,
        count: 3,
      );
      await producer.close();
      final callback = await open();
      await callback.drain();
      final draft = (await callback.workflows.viewRunDetail(
        ids.first,
      ))!.checkpoints.single;
      for (final id in ids) {
        final run = (await callback.workflows.store.get(id))!;
        expect(run.status, WorkflowStatus.suspended);
        expect(run.waitTopic, workflowApprovalTopic(id));
      }
      await callback.close();

      final approvalProducer = await open();
      await approvalProducer.controller.approve(ids.first);
      await approvalProducer.controller.cancel(ids.last);
      expect(approvalProducer.workflows.isRuntimeStarted, isFalse);
      await expectLater(
        approvalProducer.controller.approve(ids.last),
        throwsStateError,
      );
      await approvalProducer.close();

      final second = await open();
      await second.drain();
      final released = (await second.workflows.viewRunDetail(ids.first))!;
      expect(
        released.run.status,
        WorkflowStatus.completed,
        reason: '${released.toJson()}',
      );
      expect((released.run.result as Map)['approved'], isTrue);
      final replayed = released.checkpoints.singleWhere(
        (step) => step.checkpointName == 'draft',
      );
      expect(replayed.completedAt, draft.completedAt);
      expect(replayed.value, draft.value);
      expect(
        (await second.workflows.viewRun(ids[1]))!.status,
        WorkflowStatus.suspended,
      );
      expect(
        (await second.workflows.viewRun(ids.last))!.status,
        WorkflowStatus.cancelled,
      );
    },
  );

  test(
    'dispose joins a durable mutation and pending reads, wakeup follows write',
    () async {
      final session = await open();
      final entered = Completer<void>();
      final release = Completer<void>();
      final controller = WorkflowWorkbenchController(
        session.workflows,
        requestWakeup: () async {
          expect(await session.workflows.listRunViews(), hasLength(1));
          entered.complete();
          await release.future;
        },
      );
      final launch = controller.launch(WorkbenchWorkflowKind.report);
      await entered.future;
      final read = controller.refresh();
      var closed = false;
      final closing = controller.dispose().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      release.complete();
      await launch;
      await read;
      await closing;
      expect(controller.runs, hasLength(1));
      await expectLater(
        controller.launch(WorkbenchWorkflowKind.report),
        throwsStateError,
      );
      expect(session.app.isStarted, isFalse);
    },
  );
}

class _Session {
  _Session(this.app, this.workflows)
    : controller = WorkflowWorkbenchController(workflows);

  final StemApp app;
  final StemWorkflowApp workflows;
  final WorkflowWorkbenchController controller;
  bool _closed = false;

  Future<void> drain() async {
    await prepareDemoWorkflowCallback(workflows);
    final outcome = await app.worker.runUntilIdle(
      budget: const Duration(seconds: 10),
      shutdownReserve: const Duration(seconds: 1),
      idleTimeout: const Duration(milliseconds: 100),
    );
    expect(outcome.reason, WorkerRunStopReason.idle);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await controller.dispose();
    await app.worker.shutdown();
    await workflows.close();
    await app.close();
  }
}
