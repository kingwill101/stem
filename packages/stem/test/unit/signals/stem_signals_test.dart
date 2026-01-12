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

    await emitter.workerReady(worker);
    await emitter.workerReady(otherWorker);

    expect(failures, ['target.task']);
    expect(workerEvents, ['worker-1']);
  });

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
}
