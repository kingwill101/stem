import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_stem_example/src/demo_config.dart';
import 'package:flutter_stem_example/src/demo_tasks.dart';
import 'package:flutter_stem_example/src/photo_batch.dart';
import 'package:stem/memory.dart';
import 'package:stem/stem.dart';

class ControlledBroker extends InMemoryBroker {
  int publishes = 0;
  int? failAt;
  Completer<void>? gate;
  final entered = Completer<void>();

  @override
  Future<void> publish(Envelope envelope, {RoutingInfo? routing}) async {
    publishes++;
    if (!entered.isCompleted) entered.complete();
    await gate?.future;
    if (publishes == failAt) throw StateError('publish unavailable');
    await super.publish(envelope, routing: routing);
  }
}

void main() {
  late ControlledBroker broker;
  late StemApp app;
  late PhotoBatchProducer producer;
  var wakeups = 0;
  setUp(() async {
    wakeups = 0;
    broker = ControlledBroker();
    app = await StemApp.create(
      module: demoModule,
      broker: StemBrokerFactory(
        create: () async => broker,
        dispose: (broker) => (broker as ControlledBroker).close(),
      ),
      backend: StemBackendFactory.inMemory(),
      workerConfig: const StemWorkerConfig(concurrency: 1),
    );
    producer = PhotoBatchProducer(
      app,
      outputDirectory: '/unused/no-worker',
      requestWakeup: () async {
        wakeups++;
      },
    );
  });
  tearDown(() async {
    await producer.dispose();
    await app.close();
  });

  test(
    'partial publication reports commits and still requests wakeup',
    () async {
      broker.failAt = 2;
      final message = await producer.publish(PhotoWorkload.standard);
      expect(message, contains('1 of 6 photos committed'));
      expect(message, contains('Publication stopped'));
      expect(wakeups, 1);
      expect(await broker.pendingCount(queueName), 1);
      await producer.publish(PhotoWorkload.standard);
      expect(
        broker.publishes,
        2,
        reason: 'Unfinished work blocks another batch.',
      );
    },
  );

  test(
    'dispose joins current commit and prevents subsequent publishes',
    () async {
      broker.gate = Completer<void>();
      final publishing = producer.publish(PhotoWorkload.standard);
      await broker.entered.future;
      var closed = false;
      final closing = producer.dispose().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      broker.gate!.complete();
      expect(await publishing, contains('1 of 6 photos committed'));
      await closing;
      expect(broker.publishes, 1);
      expect(wakeups, 1);
      await producer.publish(PhotoWorkload.standard);
      expect(broker.publishes, 1);
    },
  );

  test(
    'notification failure does not block committed work or scheduling',
    () async {
      producer = PhotoBatchProducer(
        app,
        outputDirectory: '/unused/no-worker',
        requestWakeup: () async {
          wakeups++;
        },
        onCommitted: (_) async => throw StateError('notifications denied'),
      );
      final message = await producer.publish(PhotoWorkload.quick);
      expect(message, contains('3 of 3 photos committed'));
      expect(wakeups, 1);
      expect(broker.publishes, 3);
      expect(await broker.pendingCount(queueName), 3);
    },
  );

  test('persisted batch accounting keeps uncommitted photos distinct', () {
    final now = DateTime.now();
    final jobs = [
      for (final state in [
        TaskState.succeeded,
        TaskState.failed,
        TaskState.running,
        TaskState.queued,
      ])
        TaskStatusRecord(
          status: TaskStatus(
            id: state.name,
            state: state,
            attempt: 1,
            meta: {'batchId': 'batch', 'batchSize': 6, 'label': 'Standard'},
            payload: state == TaskState.succeeded
                ? {'elapsedMs': 120, 'sourceBytes': 1000, 'outputBytes': 250}
                : null,
          ),
          createdAt: now,
          updatedAt: now,
        ),
    ];
    final summary = PhotoBatchSummary.fromJobs(jobs).single;
    expect(summary.planned, 6);
    expect(summary.jobs.length, 4);
    expect(summary.completed, 2);
    expect(summary.fraction, 2 / 6);
    expect(summary.running, 1);
    expect(summary.queued, 1);
    expect(summary.metric('elapsedMs'), 120);
    expect(summary.metric('outputBytes'), 250);
  });
}
