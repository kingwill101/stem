import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_stem_example/src/demo_config.dart';
import 'package:flutter_stem_example/src/demo_workers.dart';
import 'package:flutter_stem_example/src/demo_workflows.dart';
import 'package:flutter_stem_example/src/routing_tasks.dart';
import 'package:stem/stem.dart' show FunctionTaskHandler;
import 'package:stem_flutter_sqlite/stem_flutter_sqlite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late StemFlutterStorageLayout layout;
  final workers = <DemoWorkerRuntime>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('stem-workers-');
    layout = await StemFlutterStorageLayout.forRoot(directory);
  });
  tearDown(() async {
    await Future.wait(workers.map((worker) => worker.close()));
    workers.clear();
    await directory.delete(recursive: true);
  });

  Future<DemoWorkerRuntime> open(int index) async {
    final worker = await createDemoWorker(
      demoWorkerSpecs[index],
      layout: layout,
    );
    workers.add(worker);
    return worker;
  }

  Future<WorkerRunOutcome> drain(DemoWorkerRuntime worker) async {
    await worker.prepareBounded();
    return worker.runUntilIdle(
      budget: const Duration(seconds: 15),
      shutdownReserve: const Duration(seconds: 1),
      // Longer than the production SQLite broker's 250ms poll interval.
      idleTimeout: const Duration(seconds: 1),
    );
  }

  test(
    'two normal same-file workers independently lease gated deliveries',
    () async {
      final first = await open(0);
      final second = await open(1);
      final entered = [Completer<void>(), Completer<void>()];
      final release = Completer<void>();
      final executions = <String, int>{};
      for (var i = 0; i < 2; i++) {
        final index = i;
        workers[i].app.register(
          FunctionTaskHandler<Map<String, Object?>>.inline(
            name: 'test.gated',
            options: const TaskOptions(queue: queueName),
            entrypoint: (_, args) async {
              final key = args['key']! as String;
              executions.update(key, (count) => count + 1, ifAbsent: () => 1);
              entered[index].complete();
              await release.future;
              return {'key': key};
            },
          ),
        );
      }
      final ids = [
        await first.app.enqueue('test.gated', args: {'key': 'one'}),
        await first.app.enqueue('test.gated', args: {'key': 'two'}),
      ];
      try {
        await first.start();
        await entered[0].future.timeout(const Duration(seconds: 5));
        await second.start();
        await entered[1].future.timeout(const Duration(seconds: 5));
      } finally {
        release.complete();
      }
      final statuses = await Future.wait(
        ids.map((id) => _completed(first.app, id)),
      );
      expect(ids.toSet(), hasLength(2));
      expect(executions, {'one': 1, 'two': 1});
      expect(
        statuses.map((status) => status.meta['worker']),
        unorderedEquals(['general-a', 'general-b']),
      );
      expect(
        statuses.map((status) => (status.payload as Map)['key']),
        unorderedEquals(['one', 'two']),
      );
      await first.close();
      await first.close();
      await second.close();
      final observer = await open(2);
      for (final id in ids) {
        expect(
          (await observer.app.getTaskStatus(id))?.state,
          TaskState.succeeded,
        );
      }
    },
  );

  test(
    'dedicated queue drains independently and preserves typed probe results',
    () async {
      final general = await open(0);
      final routing = await open(2);
      expect(routing.workflows, isNull);
      final generalIds = await enqueueRoutingProbes(
        general.app,
        queue: queueName,
        count: 2,
      );
      final routingIds = await enqueueRoutingProbes(
        general.app,
        queue: routingQueueName,
        count: 2,
      );
      final routed = await drain(routing);
      expect(routed.reason, WorkerRunStopReason.idle);
      expect(routed.deliveriesProcessed, 2);
      for (final id in generalIds) {
        expect((await general.app.getTaskStatus(id))?.state, TaskState.queued);
      }
      for (final id in routingIds) {
        final status = (await general.app.getTaskStatus(id))!;
        expect(status.state, TaskState.succeeded);
        expect(status.meta['worker'], 'routing-worker');
        expect(status.meta.containsKey('batchId'), isFalse);
        expect((status.payload as Map)['checksum'], matches(r'^[0-9a-f]{64}$'));
      }
      final ordinary = await drain(general);
      expect(ordinary.deliveriesProcessed, 2);
      for (final id in generalIds) {
        expect(
          (await general.app.getTaskStatus(id))?.meta['worker'],
          'general-a',
        );
      }
      expect({...generalIds, ...routingIds}, hasLength(4));
    },
  );

  test(
    'report published by one general runtime executes on the other',
    () async {
      final producer = await open(0);
      final consumer = await open(1);
      final id = await producer.workflows!.runtime.startWorkflow(
        WorkbenchWorkflowKind.report.descriptor.name,
      );
      final outcome = await drain(consumer);
      expect(outcome.reason, WorkerRunStopReason.idle);
      final detail = (await producer.workflows!.viewRunDetail(id))!;
      expect(detail.run.status, WorkflowStatus.completed);
      expect(detail.run.result, {'rows': 3, 'total': 35});
      expect(
        detail.checkpoints.map((item) => item.checkpointName),
        unorderedEquals(['collect', 'total', 'publish']),
      );
    },
  );

  test('bounded idle belongs only to each subscription', () async {
    final general = await open(0);
    final routing = await open(2);
    final entered = Completer<void>();
    final release = Completer<void>();
    general.app.register(
      FunctionTaskHandler<void>.inline(
        name: 'test.held',
        options: const TaskOptions(queue: queueName),
        entrypoint: (_, _) async {
          entered.complete();
          await release.future;
          return null;
        },
      ),
    );
    await general.app.enqueue('test.held');
    final generalRun = drain(general);
    try {
      await entered.future.timeout(const Duration(seconds: 5));
      final idle = await drain(routing);
      expect(idle.reason, WorkerRunStopReason.idle);
      expect(idle.deliveriesProcessed, 0);
    } finally {
      release.complete();
      await generalRun;
    }
  });

  test(
    'probe publication bounds and batch metadata are isolated from photos',
    () async {
      final worker = await open(2);
      for (final count in [0, 7]) {
        await expectLater(
          enqueueRoutingProbes(
            worker.app,
            queue: routingQueueName,
            count: count,
          ),
          throwsRangeError,
        );
      }
      await expectLater(
        enqueueRoutingProbes(worker.app, queue: 'unknown'),
        throwsArgumentError,
      );
      final one = await enqueueRoutingProbes(
        worker.app,
        queue: routingQueueName,
        count: 1,
      );
      final two = await enqueueRoutingProbes(
        worker.app,
        queue: routingQueueName,
        count: 1,
      );
      final a = (await worker.app.getTaskStatus(one.single))!;
      final b = (await worker.app.getTaskStatus(two.single))!;
      expect(a.meta['probeBatchId'], isNot(b.meta['probeBatchId']));
      expect(a.meta.containsKey('batchId'), isFalse);
    },
  );
}

Future<TaskStatus> _completed(StemApp app, String id) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    final status = await app.getTaskStatus(id);
    if (status?.state == TaskState.succeeded) return status!;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw TimeoutException('Task $id did not complete');
}
