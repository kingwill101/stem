import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_dashboard/dashboard.dart';
import 'package:stem_dashboard/src/config/config.dart';
import 'package:stem_sqlite/stem_sqlite.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File dbFile;
  late StemDashboardService service;
  late SqliteBroker broker;
  late SqliteResultBackend backend;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('stem_dashboard_sqlite_test');
    dbFile = File('${tempDir.path}/dashboard.db');

    // Create broker and backend instances
    broker = await SqliteBroker.open(dbFile);
    backend = await SqliteResultBackend.open(dbFile);

    // Create a minimal config for the dashboard
    final config = DashboardConfig.fromEnvironment({
      'STEM_BROKER_URL': 'sqlite:///${dbFile.path}',
      'STEM_RESULT_BACKEND_URL': 'sqlite:///${dbFile.path}',
      'STEM_WORKER_QUEUES': 'pending-queue,dead-queue,inflight-queue',
    });

    // Use fromInstances to inject our broker and backend
    service = await StemDashboardService.fromInstances(
      config: config,
      broker: broker,
      backend: backend,
    );
  });

  tearDown(() async {
    await service.close();
    await broker.close();
    await backend.close();
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
    await tempDir.delete(recursive: true);
  });

  test(
    'fetchQueueSummaries aggregates pending, inflight, and dead counts',
    () async {
      await broker.publish(
        Envelope(name: 'pending', args: const {}, queue: 'pending-queue'),
      );

      await broker.publish(
        Envelope(name: 'dead', args: const {}, queue: 'dead-queue'),
      );
      final deadDelivery = await broker
          .consume(RoutingSubscription.singleQueue('dead-queue'))
          .first;
      await broker.nack(deadDelivery, requeue: false);

      await broker.publish(
        Envelope(name: 'inflight', args: const {}, queue: 'inflight-queue'),
      );
      await broker
          .consume(RoutingSubscription.singleQueue('inflight-queue'))
          .first;

      final summaries = await service.fetchQueueSummaries();
      final pendingSummary = summaries.firstWhere(
        (summary) => summary.queue == 'pending-queue',
      );
      final deadSummary = summaries.firstWhere(
        (summary) => summary.queue == 'dead-queue',
      );
      final inflightSummary = summaries.firstWhere(
        (summary) => summary.queue == 'inflight-queue',
      );

      expect(pendingSummary.pending, 1);
      expect(pendingSummary.inflight, 0);
      expect(pendingSummary.deadLetters, 0);

      expect(deadSummary.pending, 0);
      expect(deadSummary.deadLetters, 1);

      expect(inflightSummary.inflight, 1);
    },
  );

  test('fetchWorkerStatuses reads heartbeats from the database', () async {
    await backend.setWorkerHeartbeat(
      WorkerHeartbeat(
        workerId: 'worker-sqlite',
        namespace: 'stem',
        timestamp: DateTime.now(),
        isolateCount: 1,
        inflight: 0,
        queues: [QueueHeartbeat(name: 'default', inflight: 0)],
      ),
    );

    final workers = await service.fetchWorkerStatuses();
    expect(workers, hasLength(1));
    expect(workers.first.workerId, 'worker-sqlite');
  });
}
