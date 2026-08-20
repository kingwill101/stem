import 'dart:async';
import 'dart:io';

import 'package:stem/memory.dart';
import 'package:stem/stem.dart';
import 'package:stem_sqlite/stem_sqlite.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'stem_sqlite_workflow_restart_test',
    );
    dbFile = File('${tempDir.path}/workflow.db');
  });

  tearDown(() async {
    if (dbFile.existsSync()) {
      await dbFile.delete();
    }
    await tempDir.delete(recursive: true);
  });

  test(
    'resumes a persisted checkpoint after broker and runtime restart',
    () async {
      final clock = FakeWorkflowClock(DateTime.utc(2026));
      final brokerBeforeRestart = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 5),
      );
      final backendBeforeRestart = InMemoryResultBackend();
      final registryBeforeRestart = InMemoryTaskRegistry();
      final storeBeforeRestart = await SqliteWorkflowStore.open(
        dbFile,
        clock: clock,
      );
      final runtimeBeforeRestart = WorkflowRuntime(
        stem: Stem(
          broker: brokerBeforeRestart,
          registry: registryBeforeRestart,
          backend: backendBeforeRestart,
        ),
        store: storeBeforeRestart,
        eventBus: InMemoryEventBus(storeBeforeRestart),
        clock: clock,
        pollInterval: const Duration(milliseconds: 5),
        leaseExtension: const Duration(seconds: 5),
        runLeaseDuration: const Duration(seconds: 5),
        runtimeId: 'workflow-runtime-before-restart',
      );
      registryBeforeRestart.register(
        runtimeBeforeRestart.workflowRunnerHandler(),
      );
      var checkpointExecutions = 0;
      final workflow = Flow(
        name: 'restart.recovery.workflow',
        build: (flow) {
          flow
            ..step('checkpoint', (context) async {
              checkpointExecutions += 1;
              return 'persisted';
            })
            ..step('wait', (context) async {
              if (context.takeResumeData() == true) {
                return 'resumed';
              }
              context.sleep(const Duration(milliseconds: 20));
              return null;
            })
            ..step(
              'finish',
              (context) async => '${context.previousResult}-done',
            );
        },
      ).definition;
      runtimeBeforeRestart.registerWorkflow(workflow);
      final workerBeforeRestart = Worker(
        broker: brokerBeforeRestart,
        backend: backendBeforeRestart,
        tasks: [runtimeBeforeRestart.workflowRunnerHandler()],
        queue: 'workflow',
        subscription: RoutingSubscription.singleQueue('workflow'),
        consumerName: 'workflow-worker-before-restart',
        concurrency: 1,
        prefetchMultiplier: 1,
        retryStrategy: ExponentialJitterRetryStrategy(
          base: const Duration(milliseconds: 5),
          max: const Duration(milliseconds: 20),
          seed: 1,
        ),
        lifecycle: const WorkerLifecycleConfig(
          installSignalHandlers: false,
        ),
      );

      final runId = await _runBeforeRestart(
        clock: clock,
        runtime: runtimeBeforeRestart,
        store: storeBeforeRestart,
        worker: workerBeforeRestart,
        workflowName: workflow.name,
      );
      expect(checkpointExecutions, equals(1));

      await workerBeforeRestart.shutdown();
      await runtimeBeforeRestart.dispose();
      await storeBeforeRestart.close();
      brokerBeforeRestart.dispose();

      final brokerAfterRestart = InMemoryBroker(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 5),
      );
      final backendAfterRestart = InMemoryResultBackend();
      final registryAfterRestart = InMemoryTaskRegistry();
      final storeAfterRestart = await SqliteWorkflowStore.open(
        dbFile,
        clock: clock,
      );
      final runtimeAfterRestart = WorkflowRuntime(
        stem: Stem(
          broker: brokerAfterRestart,
          registry: registryAfterRestart,
          backend: backendAfterRestart,
        ),
        store: storeAfterRestart,
        eventBus: InMemoryEventBus(storeAfterRestart),
        clock: clock,
        pollInterval: const Duration(milliseconds: 5),
        leaseExtension: const Duration(seconds: 5),
        runLeaseDuration: const Duration(seconds: 5),
        runtimeId: 'workflow-runtime-after-restart',
      )..registerWorkflow(workflow);
      registryAfterRestart.register(
        runtimeAfterRestart.workflowRunnerHandler(),
      );
      final workerAfterRestart = Worker(
        broker: brokerAfterRestart,
        backend: backendAfterRestart,
        tasks: [runtimeAfterRestart.workflowRunnerHandler()],
        queue: 'workflow',
        subscription: RoutingSubscription.singleQueue('workflow'),
        consumerName: 'workflow-worker-after-restart',
        concurrency: 1,
        prefetchMultiplier: 1,
        lifecycle: const WorkerLifecycleConfig(
          installSignalHandlers: false,
        ),
      );

      try {
        await runtimeAfterRestart.start();
        await workerAfterRestart.start();
        clock.advance(const Duration(milliseconds: 30));

        await _waitForRun(
          storeAfterRestart,
          runId,
          (state) => state?.status == WorkflowStatus.completed,
        );

        final completed = await storeAfterRestart.get(runId);
        expect(completed?.result, equals('resumed-done'));
        expect(checkpointExecutions, equals(1));
      } finally {
        await workerAfterRestart.shutdown();
        await runtimeAfterRestart.dispose();
        await storeAfterRestart.close();
        brokerAfterRestart.dispose();
      }
    },
  );
}

Future<String> _runBeforeRestart({
  required FakeWorkflowClock clock,
  required WorkflowRuntime runtime,
  required WorkflowStore store,
  required Worker worker,
  required String workflowName,
}) async {
  await worker.start();
  final runId = await runtime.startWorkflow(workflowName);
  await _waitForRun(
    store,
    runId,
    (state) => state?.status == WorkflowStatus.suspended,
  );
  expect(clock.now(), equals(DateTime.utc(2026)));
  return runId;
}

Future<void> _waitForRun(
  WorkflowStore store,
  String runId,
  bool Function(RunState? state) predicate, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    if (predicate(await store.get(runId))) {
      return;
    }
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(
        'Workflow $runId did not reach the expected state',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
