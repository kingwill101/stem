import 'package:stem/src/control/control_messages.dart';
import 'package:stem/src/core/envelope.dart';
import 'package:stem/src/signals/emitter.dart';
import 'package:stem/src/signals/payloads.dart';
import 'package:stem/src/signals/stem_signals.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() {
    StemSignals.configure(configuration: const StemSignalConfiguration());
  });

  test('StemSignals.configure toggles signal enablement', () async {
    final envelope = Envelope(name: 'demo.signal', args: const {});
    final events = <String>[];

    final sub = StemSignals.onBeforeTaskPublish((payload, _) {
      events.add(payload.envelope.name);
    });
    addTearDown(sub.cancel);

    StemSignals.configure(
      configuration: const StemSignalConfiguration(
        enabledSignals: {StemSignals.beforeTaskPublishName: false},
      ),
    );

    const emitter = StemSignalEmitter();
    await emitter.beforeTaskPublish(envelope);
    expect(events, isEmpty);

    StemSignals.configure(configuration: const StemSignalConfiguration());
    await emitter.beforeTaskPublish(envelope);
    expect(events, ['demo.signal']);
  });

  test('StemSignals filters by task name and worker id', () async {
    final envelope = Envelope(name: 'target.task', args: const {});
    final other = Envelope(name: 'other.task', args: const {});
    const worker = WorkerInfo(
      id: 'worker-1',
      queues: ['default'],
      broadcasts: [],
    );
    const otherWorker = WorkerInfo(
      id: 'worker-2',
      queues: ['default'],
      broadcasts: [],
    );

    final failures = <String>[];
    final workerEvents = <String>[];

    final failureSub = StemSignals.onTaskFailure(
      (payload, _) => failures.add(payload.envelope.name),
      taskName: 'target.task',
      workerId: 'worker-1',
    );
    final readySub = StemSignals.onWorkerReady(
      (payload, _) => workerEvents.add(payload.worker.id),
      workerId: 'worker-1',
    );

    addTearDown(() {
      failureSub.cancel();
      readySub.cancel();
    });

    const emitter = StemSignalEmitter();
    await emitter.taskFailed(
      envelope,
      worker,
      error: StateError('fail'),
    );
    await emitter.taskFailed(
      other,
      worker,
      error: StateError('fail'),
    );
    await emitter.taskFailed(
      envelope,
      otherWorker,
      error: StateError('fail'),
    );

    await emitter.workerReady(worker);
    await emitter.workerReady(otherWorker);

    expect(failures, ['target.task']);
    expect(workerEvents, ['worker-1']);
  });

  test(
    'StemSignals supports worker-scoped lifecycle and control subscriptions',
    () async {
      const workerA = WorkerInfo(
        id: 'worker-a',
        queues: ['default'],
        broadcasts: [],
      );
      const workerB = WorkerInfo(
        id: 'worker-b',
        queues: ['default'],
        broadcasts: [],
      );

      final lifecycle = <String>[];
      final control = <String>[];
      final subs = [
        StemSignals.onWorkerInit(
          (payload, _) => lifecycle.add(payload.worker.id),
          workerId: workerA.id,
        ),
        StemSignals.onWorkerStopping(
          (payload, _) => lifecycle.add(payload.worker.id),
          workerId: workerA.id,
        ),
        StemSignals.onWorkerShutdown(
          (payload, _) => lifecycle.add(payload.worker.id),
          workerId: workerA.id,
        ),
        StemSignals.onControlCommandReceived(
          (payload, _) =>
              control.add('${payload.worker.id}:${payload.command.type}'),
          workerId: workerA.id,
          commandType: 'ping',
        ),
        StemSignals.onControlCommandCompleted(
          (payload, _) => control.add(
            '${payload.worker.id}:${payload.command.type}:${payload.status}',
          ),
          workerId: workerA.id,
          commandType: 'ping',
        ),
      ];
      addTearDown(() {
        for (final sub in subs) {
          sub.cancel();
        }
      });

      const emitter = StemSignalEmitter();
      await emitter.workerInit(workerA);
      await emitter.workerInit(workerB);
      await emitter.workerStopping(workerA);
      await emitter.workerStopping(workerB);
      await emitter.workerShutdown(workerA);
      await emitter.workerShutdown(workerB);

      final pingA = ControlCommandMessage(
        requestId: 'req-a',
        type: 'ping',
        targets: ['*'],
      );
      final pauseA = ControlCommandMessage(
        requestId: 'req-b',
        type: 'pause',
        targets: ['*'],
      );
      final pingB = ControlCommandMessage(
        requestId: 'req-c',
        type: 'ping',
        targets: ['*'],
      );
      await emitter.controlCommandReceived(workerA, pingA);
      await emitter.controlCommandReceived(workerA, pauseA);
      await emitter.controlCommandReceived(workerB, pingB);
      await emitter.controlCommandCompleted(
        workerA,
        pingA,
        status: 'ok',
      );
      await emitter.controlCommandCompleted(
        workerA,
        pauseA,
        status: 'ok',
      );
      await emitter.controlCommandCompleted(
        workerB,
        pingB,
        status: 'ok',
      );

      expect(lifecycle, equals(['worker-a', 'worker-a', 'worker-a']));
      expect(control, equals(['worker-a:ping', 'worker-a:ping:ok']));
    },
  );

  test('StemSignals forwards errors to configured reporter', () async {
    Object? capturedError;
    String? capturedSignal;

    StemSignals.configure(
      onError: (signal, error, _) {
        capturedSignal = signal;
        capturedError = error;
      },
    );

    final sub = StemSignals.onAfterTaskPublish((payload, _) {
      throw StateError('boom');
    });
    addTearDown(sub.cancel);

    final envelope = Envelope(name: 'demo.error', args: const {});
    const emitter = StemSignalEmitter();
    await emitter.afterTaskPublish(envelope);

    expect(capturedSignal, StemSignals.afterTaskPublishName);
    expect(capturedError, isA<StateError>());
  });

  test('emitted payloads use canonical signal names', () async {
    String? workerEventName;
    String? workflowStartedName;
    String? workflowResumedName;

    final workerSub = StemSignals.workerReady.connect((payload, _) {
      workerEventName = payload.eventName;
    });
    final startedSub = StemSignals.workflowRunStarted.connect((payload, _) {
      workflowStartedName = payload.eventName;
    });
    final resumedSub = StemSignals.workflowRunResumed.connect((payload, _) {
      workflowResumedName = payload.eventName;
    });

    addTearDown(() {
      workerSub.cancel();
      startedSub.cancel();
      resumedSub.cancel();
    });

    const emitter = StemSignalEmitter();
    const worker = WorkerInfo(
      id: 'worker-events',
      queues: ['default'],
      broadcasts: [],
    );

    await emitter.workerReady(worker);
    await emitter.workflowRunStarted(
      WorkflowRunPayload(
        runId: 'run-1',
        workflow: 'wf',
        status: WorkflowRunStatus.running,
      ),
    );
    await emitter.workflowRunResumed(
      WorkflowRunPayload(
        runId: 'run-2',
        workflow: 'wf',
        status: WorkflowRunStatus.running,
      ),
    );

    expect(workerEventName, StemSignals.workerReadyName);
    expect(workflowStartedName, StemSignals.workflowRunStartedName);
    expect(workflowResumedName, StemSignals.workflowRunResumedName);
  });
}
