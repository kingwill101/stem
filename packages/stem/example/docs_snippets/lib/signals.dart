// Signal configuration example for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:async';

import 'package:stem/stem.dart';

// #region signals-configure
void configureSignals() {
  StemSignals.configure(
    configuration: const StemSignalConfiguration(
      enabled: true,
      enabledSignals: {'worker-heartbeat': false},
    ),
  );
}
// #endregion signals-configure

// #region signals-task-listeners
List<SignalSubscription> registerTaskSignals() {
  return [
    StemSignals.taskRetry.connect((payload, _) {
      print('Retrying ${payload.envelope.name} at ${payload.nextRetryAt}');
    }),
    StemSignals.taskFailed.connect((payload, _) {
      print('Task failed: ${payload.envelope.id}');
    }),
  ];
}
// #endregion signals-task-listeners

// #region signals-worker-listeners
SignalSubscription registerWorkerSignals() {
  return StemSignals.workerReady.connect((payload, _) {
    print('Worker ready: ${payload.worker.id}');
  });
}
// #endregion signals-worker-listeners

// #region signals-scheduler-listeners
SignalSubscription registerSchedulerSignals() {
  return StemSignals.scheduleEntryDispatched.connect((payload, _) {
    print('Schedule dispatched: ${payload.entry.id}');
  });
}
// #endregion signals-scheduler-listeners

// #region signals-control-listeners
SignalSubscription registerControlSignals() {
  return StemSignals.controlCommandCompleted.connect((payload, _) {
    print('Control command: ${payload.command.type}');
  });
}
// #endregion signals-control-listeners

// #region signals-middleware
List<Middleware> buildSignalMiddlewareForProducer() {
  return [SignalMiddleware.coordinator()];
}

List<Middleware> buildSignalMiddlewareForWorker() {
  return [
    SignalMiddleware.worker(
      workerInfo: () => const WorkerInfo(
        id: 'signals-worker',
        queues: ['default'],
        broadcasts: [],
      ),
    ),
  ];
}
// #endregion signals-middleware

Future<void> main() async {
  configureSignals();
  final subscriptions = <SignalSubscription>[
    ...registerTaskSignals(),
    registerWorkerSignals(),
    registerSchedulerSignals(),
    registerControlSignals(),
  ];

  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<void>(
        name: 'signals.demo',
        entrypoint: (context, args) async {
          print('Signals demo task');
          return null;
        },
      ),
    );
  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();
  final stem = Stem(
    broker: broker,
    registry: registry,
    backend: backend,
    middleware: buildSignalMiddlewareForProducer(),
  );
  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    middleware: buildSignalMiddlewareForWorker(),
  );

  unawaited(worker.start());
  await stem.enqueue('signals.demo', args: const {});
  await Future<void>.delayed(const Duration(milliseconds: 200));
  await worker.shutdown();

  for (final subscription in subscriptions) {
    subscription.cancel();
  }
  broker.dispose();
  await backend.dispose();
}
