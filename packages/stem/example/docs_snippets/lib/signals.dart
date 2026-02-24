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

// #region signals-publish-listeners
List<SignalSubscription> registerPublishSignals() {
  return [
    StemSignals.beforeTaskPublish.connect((payload, _) {
      print('Publishing ${payload.envelope.name}');
    }),
    StemSignals.afterTaskPublish.connect((payload, _) {
      print('Published ${payload.envelope.id}');
    }),
  ];
}
// #endregion signals-publish-listeners

// #region signals-worker-listeners
SignalSubscription registerWorkerSignals() {
  return StemSignals.onWorkerReady((payload, _) {
    print('Worker ready: ${payload.worker.id}');
  }, workerId: 'signals-worker');
}
// #endregion signals-worker-listeners

// #region signals-worker-scoped
List<SignalSubscription> registerWorkerScopedSignals() {
  return [
    StemSignals.onTaskFailure(
      (payload, _) {
        print(
          'Task failed on worker ${payload.worker.id}: ${payload.taskName}',
        );
      },
      taskName: 'signals.demo',
      workerId: 'signals-worker',
    ),
    StemSignals.onControlCommandCompleted(
      (payload, _) {
        print(
          'Control ${payload.command.type} -> ${payload.status} on ${payload.worker.id}',
        );
      },
      workerId: 'signals-worker',
      commandType: 'ping',
    ),
  ];
}
// #endregion signals-worker-scoped

// #region signals-stem-event
SignalSubscription registerStemEventView() {
  return StemSignals.onTaskSuccess((payload, context) {
    final event = context.event;
    if (event != null) {
      print(
        'Event ${event.eventName} at ${event.occurredAt.toIso8601String()}',
      );
    }
  });
}
// #endregion signals-stem-event

// #region signals-scheduler-listeners
SignalSubscription registerSchedulerSignals() {
  return StemSignals.scheduleEntryDispatched.connect((payload, _) {
    print('Schedule dispatched: ${payload.entry.id}');
  });
}
// #endregion signals-scheduler-listeners

// #region signals-control-listeners
SignalSubscription registerControlSignals() {
  return StemSignals.onControlCommandCompleted((payload, _) {
    print('Control command: ${payload.command.type}');
  });
}
// #endregion signals-control-listeners

// #region signals-middleware-producer
List<Middleware> buildSignalMiddlewareForProducer() {
  return [SignalMiddleware.coordinator()];
}

// #endregion signals-middleware-producer

// #region signals-middleware-worker
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
// #endregion signals-middleware-worker

Future<void> main() async {
  configureSignals();
  final subscriptions = <SignalSubscription>[
    ...registerPublishSignals(),
    ...registerTaskSignals(),
    registerWorkerSignals(),
    ...registerWorkerScopedSignals(),
    registerStemEventView(),
    registerSchedulerSignals(),
    registerControlSignals(),
  ];

  final app = await StemApp.fromUrl(
    'memory://',
    tasks: [
      FunctionTaskHandler<void>(
        name: 'signals.demo',
        entrypoint: (context, args) async {
          print('Signals demo task');
          return null;
        },
      ),
    ],
    middleware: buildSignalMiddlewareForProducer(),
    workerConfig: StemWorkerConfig(
      middleware: buildSignalMiddlewareForWorker(),
    ),
  );

  unawaited(app.start());
  await app.stem.enqueue('signals.demo', args: const {});
  await Future<void>.delayed(const Duration(milliseconds: 200));
  await app.close();

  for (final subscription in subscriptions) {
    subscription.cancel();
  }
}
