import 'dart:async';
import 'dart:isolate';

import 'package:stem/stem.dart';
import 'package:stem/observability.dart';
import 'package:stem_flutter/stem_flutter.dart';
import 'package:stem_flutter_sqlite/stem_flutter_sqlite.dart';

import '../demo_config.dart';
import '../demo_tasks.dart';

@pragma('vm:entry-point')
Future<void> workerIsolateMain(Map<String, Object?> config) async {
  final bootstrap = StemFlutterSqliteWorkerBootstrap.fromMessage(config);

  StreamSubscription<WorkerEvent>? eventsSub;
  Worker? worker;
  StemFlutterSqliteWorkerStores? stores;
  ReceivePort? commands;
  var workerStarted = false;

  try {
    configureStemLogging(
      level: StemLogLevel.debug,
      format: StemLogFormat.plain,
      enableConsole: true,
    );
    stemLogger.info('Worker isolate bootstrap starting');
    bootstrap.sendPort.send(
      const StemFlutterWorkerSignal.status(
        status: StemFlutterWorkerStatus.starting,
        detail: 'Initializing background isolate',
      ).toMessage(),
    );

    await bootstrap.initializeBackgroundDependencies();
    stemLogger.info('Worker isolate dependencies initialized');

    stores = await StemFlutterSqliteWorkerStores.open(bootstrap);
    stemLogger.info(
      'Worker stores ready',
      fields: <String, Object?>{
        'component': 'flutter_example',
        'subsystem': 'worker',
        'brokerPath': bootstrap.brokerPath,
        'backendPath': bootstrap.backendPath,
      },
    );

    worker = Worker(
      broker: stores.broker,
      backend: stores.backend,
      tasks: createTaskHandlers(),
      queue: queueName,
      consumerName: workerId,
      concurrency: 1,
      prefetch: 1,
      heartbeatInterval: workerHeartbeatInterval,
      workerHeartbeatInterval: workerHeartbeatInterval,
    );
    commands = ReceivePort();
    eventsSub = worker.events.listen((event) {
      stemLogger.info(
        'Worker event ${event.type.name}',
        fields: <String, Object?>{
          'component': 'flutter_example',
          'subsystem': 'worker_event',
          'envelopeId': event.envelopeId,
          'error': event.error?.toString(),
        },
      );
      if (event.type == WorkerEventType.error ||
          event.type == WorkerEventType.timeout) {
        bootstrap.sendPort.send(
          StemFlutterWorkerSignal.warning(
            event.error?.toString() ?? event.type.name,
          ).toMessage(),
        );
      }
    });

    await worker.start();
    workerStarted = true;
    stemLogger.info('Worker started');
    bootstrap.sendPort.send(
      StemFlutterWorkerSignal.ready(
        commandPort: commands.sendPort,
        detail: 'Worker isolate ready.',
      ).toMessage(),
    );

    await for (final dynamic message in commands) {
      if (message is Map && message['type'] == 'shutdown') {
        stemLogger.info('Worker isolate received shutdown request');
        break;
      }
    }
  } catch (error, stackTrace) {
    stemLogger.error(
      'Worker isolate bootstrap failed: $error',
      stackTrace: stackTrace,
    );
    bootstrap.sendPort.send(
      StemFlutterWorkerSignal.fatal('$error\n$stackTrace').toMessage(),
    );
  } finally {
    await eventsSub?.cancel();
    if (worker != null && workerStarted) {
      await worker.shutdown(mode: WorkerShutdownMode.warm);
    }
    await stores?.close();
    commands?.close();
    stemLogger.warning('Worker isolate shutting down');
  }
}
