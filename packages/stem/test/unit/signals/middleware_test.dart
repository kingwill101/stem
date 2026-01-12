import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/envelope.dart';
import 'package:stem/src/signals/middleware.dart';
import 'package:stem/src/signals/payloads.dart';
import 'package:stem/src/signals/stem_signals.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() {
    StemSignals.configure(configuration: const StemSignalConfiguration());
  });

  test('SignalMiddleware.coordinator emits before/after publish', () async {
    final events = <String>[];
    final beforeSub = StemSignals.onBeforeTaskPublish((payload, _) {
      events.add('before:${payload.envelope.name}');
    });
    final afterSub = StemSignals.onAfterTaskPublish((payload, _) {
      events.add('after:${payload.envelope.name}');
    });
    addTearDown(() {
      beforeSub.cancel();
      afterSub.cancel();
    });

    final middleware = SignalMiddleware.coordinator();
    final envelope = Envelope(name: 'demo.publish', args: const {});

    await middleware.onEnqueue(envelope, () async {
      events.add('next');
    });

    expect(events, ['before:demo.publish', 'next', 'after:demo.publish']);
  });

  test('SignalMiddleware.worker emits taskReceived and taskPrerun', () async {
    final events = <String>[];
    final receivedSub = StemSignals.onTaskReceived((payload, _) {
      events.add('received:${payload.taskName}');
    });
    final prerunSub = StemSignals.onTaskPrerun((payload, _) {
      events.add('prerun:${payload.taskName}');
    });
    addTearDown(() {
      receivedSub.cancel();
      prerunSub.cancel();
    });

    const workerInfo = WorkerInfo(
      id: 'worker-1',
      queues: ['default'],
      broadcasts: [],
    );
    final middleware = SignalMiddleware.worker(workerInfo: () => workerInfo);
    final envelope = Envelope(name: 'demo.work', args: const {});
    final delivery = Delivery(
      envelope: envelope,
      receipt: 'receipt-1',
      leaseExpiresAt: DateTime.now().add(const Duration(seconds: 30)),
    );

    await middleware.onConsume(delivery, () async {});

    final context = TaskContext(
      id: envelope.id,
      attempt: envelope.attempt,
      headers: envelope.headers,
      meta: envelope.meta,
      heartbeat: () {},
      extendLease: (_) async {},
      progress: (_, {Map<String, Object?>? data}) async {},
    );

    await middleware.onExecute(context, () async {});

    expect(events, ['received:demo.work', 'prerun:demo.work']);
  });

  test('SignalMiddleware.worker emits taskFailed on error', () async {
    final failures = <TaskFailurePayload>[];
    final failureSub = StemSignals.onTaskFailure((payload, _) {
      failures.add(payload);
    });
    addTearDown(failureSub.cancel);

    const workerInfo = WorkerInfo(
      id: 'worker-2',
      queues: ['default'],
      broadcasts: [],
    );
    final middleware = SignalMiddleware.worker(workerInfo: () => workerInfo);
    final envelope = Envelope(name: 'demo.fail', args: const {});
    final delivery = Delivery(
      envelope: envelope,
      receipt: 'receipt-2',
      leaseExpiresAt: DateTime.now().add(const Duration(seconds: 30)),
    );

    await middleware.onConsume(delivery, () async {});

    final context = TaskContext(
      id: envelope.id,
      attempt: envelope.attempt,
      headers: envelope.headers,
      meta: envelope.meta,
      heartbeat: () {},
      extendLease: (_) async {},
      progress: (_, {Map<String, Object?>? data}) async {},
    );

    await expectLater(
      () => middleware.onExecute(context, () async {
        throw StateError('boom');
      }),
      throwsStateError,
    );

    final error = StateError('boom');
    await middleware.onError(context, error, StackTrace.current);

    expect(failures, hasLength(1));
    expect(failures.first.envelope.name, 'demo.fail');
  });
}
