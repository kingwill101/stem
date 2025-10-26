import 'dart:async';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

class ResultBackendContractSettings {
  const ResultBackendContractSettings({
    this.statusTtl = const Duration(seconds: 1),
    this.groupTtl = const Duration(seconds: 1),
    this.heartbeatTtl = const Duration(seconds: 1),
    this.settleDelay = const Duration(milliseconds: 150),
  });

  /// Time-to-live used when asserting task status expiration.
  final Duration statusTtl;

  /// Time-to-live applied to group descriptors.
  final Duration groupTtl;

  /// Heartbeat expiration window.
  final Duration heartbeatTtl;

  /// Allow adapters time to commit writes when running assertions.
  final Duration settleDelay;
}

class ResultBackendContractFactory {
  const ResultBackendContractFactory({
    required this.create,
    this.dispose,
    this.beforeStatusExpiryCheck,
  });

  final Future<ResultBackend> Function() create;
  final FutureOr<void> Function(ResultBackend backend)? dispose;
  final FutureOr<void> Function(ResultBackend backend)? beforeStatusExpiryCheck;
}

void runResultBackendContractTests({
  required String adapterName,
  required ResultBackendContractFactory factory,
  ResultBackendContractSettings settings =
      const ResultBackendContractSettings(),
}) {
  group('$adapterName result backend contract', () {
    ResultBackend? backend;

    setUp(() async {
      backend = await factory.create();
    });

    tearDown(() async {
      final instance = backend;
      if (instance == null) {
        return;
      }
      if (factory.dispose != null) {
        await factory.dispose!(instance);
      }
      backend = null;
    });

    test('set/get/watch/expire task statuses', () async {
      final currentBackend = backend!;
      const taskId = 'contract-task';
      final updates = currentBackend.watch(taskId).first;

      final error = TaskError(
        type: 'ContractError',
        message: 'boom',
        retryable: true,
        meta: const {'code': 42},
      );

      await currentBackend.set(
        taskId,
        TaskState.succeeded,
        payload: const {'value': 'done'},
        error: error,
        attempt: 3,
        meta: const {'origin': 'contract'},
      );

      await Future<void>.delayed(settings.settleDelay);

      final status = await currentBackend.get(taskId);
      expect(status, isNotNull);
      expect(status!.state, TaskState.succeeded);
      expect(status.payload, {'value': 'done'});
      expect(status.error?.type, 'ContractError');
      expect(status.attempt, 3);
      expect(status.meta['origin'], 'contract');

      final streamed = await updates.timeout(const Duration(seconds: 5));
      expect(streamed.id, taskId);
      expect(streamed.state, TaskState.succeeded);

      await currentBackend.expire(taskId, settings.statusTtl);
      await Future<void>.delayed(settings.statusTtl + settings.settleDelay);
      if (factory.beforeStatusExpiryCheck != null) {
        await factory.beforeStatusExpiryCheck!(currentBackend);
      }
      expect(await currentBackend.get(taskId), isNull);
    });

    test('group lifecycle operations', () async {
      final currentBackend = backend!;
      const groupId = 'contract-group';
      final descriptor = GroupDescriptor(
        id: groupId,
        expected: 2,
        meta: const {'purpose': 'contract'},
        ttl: settings.groupTtl,
      );

      await currentBackend.initGroup(descriptor);

      final first = TaskStatus(
        id: 'child-a',
        state: TaskState.succeeded,
        payload: const {'value': 1},
        attempt: 1,
        meta: const {'meta': true},
      );

      final afterFirst = await currentBackend.addGroupResult(groupId, first);
      expect(afterFirst, isNotNull);
      expect(afterFirst!.results.length, 1);
      expect(afterFirst.isComplete, isFalse);

      final second = TaskStatus(
        id: 'child-b',
        state: TaskState.failed,
        payload: const {'value': 2},
        attempt: 2,
        meta: const {'meta': true},
      );

      final afterSecond = await currentBackend.addGroupResult(groupId, second);
      expect(afterSecond, isNotNull);
      expect(afterSecond!.results.length, 2);
      expect(afterSecond.isComplete, isTrue);

      final fetched = await currentBackend.getGroup(groupId);
      expect(fetched, isNotNull);
      expect(fetched!.results.keys, containsAll(['child-a', 'child-b']));
      expect(fetched.meta['purpose'], 'contract');

      final missing = await currentBackend.addGroupResult(
        'missing-group',
        first,
      );
      expect(missing, isNull);
    });

    test('worker heartbeats stored and listed', () async {
      final currentBackend = backend!;
      const workerId = 'contract-worker';
      final heartbeat = WorkerHeartbeat(
        workerId: workerId,
        namespace: 'contract',
        timestamp: DateTime.now(),
        isolateCount: 1,
        inflight: 0,
        queues: [QueueHeartbeat(name: 'default', inflight: 0)],
        extras: const {'key': 'value'},
      );

      await currentBackend.setWorkerHeartbeat(heartbeat);
      await Future<void>.delayed(settings.settleDelay);

      final stored = await currentBackend.getWorkerHeartbeat(workerId);
      expect(stored, isNotNull);
      expect(stored!.workerId, workerId);
      expect(stored.queues.single.name, 'default');
      expect(stored.extras['key'], 'value');

      final heartbeats = await currentBackend.listWorkerHeartbeats();
      expect(heartbeats.any((hb) => hb.workerId == workerId), isTrue);
    });
  });
}
