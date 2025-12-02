import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

class ResultBackendContractSettings {
  const ResultBackendContractSettings({
    this.statusTtl = const Duration(seconds: 1),
    this.groupTtl = const Duration(seconds: 1),
    this.heartbeatTtl = const Duration(seconds: 1),
    this.settleDelay = const Duration(milliseconds: 150),
    this.encoders = const [JsonTaskPayloadEncoder(), _Base64ContractEncoder()],
  });

  /// Time-to-live used when asserting task status expiration.
  final Duration statusTtl;

  /// Time-to-live applied to group descriptors.
  final Duration groupTtl;

  /// Heartbeat expiration window.
  final Duration heartbeatTtl;

  /// Allow adapters time to commit writes when running assertions.
  final Duration settleDelay;

  /// List of encoders used when executing the contract.
  final List<TaskPayloadEncoder> encoders;
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
  final encoders = settings.encoders.isEmpty
      ? const [JsonTaskPayloadEncoder()]
      : settings.encoders;

  for (final encoder in encoders) {
    final encoderLabel = encoder.runtimeType.toString();
    group('$adapterName result backend contract ($encoderLabel)', () {
      ResultBackend? backend;

      setUp(() async {
        final instance = await factory.create();
        final registry = TaskPayloadEncoderRegistry(
          defaultResultEncoder: encoder,
          defaultArgsEncoder: const JsonTaskPayloadEncoder(),
        );
        backend = withTaskPayloadEncoder(instance, registry);
      });

      tearDown(() async {
        final instance = backend;
        if (instance == null) {
          return;
        }
        if (factory.dispose != null) {
          await factory.dispose!(_unwrapBackend(instance));
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

        final statusMeta = _metaWithEncoder(encoder, const {
          'origin': 'contract',
        });
        await currentBackend.set(
          taskId,
          TaskState.succeeded,
          payload: const {'value': 'done'},
          error: error,
          attempt: 3,
          meta: statusMeta,
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
          await factory.beforeStatusExpiryCheck!(
            _unwrapBackend(currentBackend),
          );
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
          meta: _metaWithEncoder(encoder, const {'meta': true}),
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
          meta: _metaWithEncoder(encoder, const {'meta': true}),
        );

        final afterSecond = await currentBackend.addGroupResult(
          groupId,
          second,
        );
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

      test('claimChord allows only a single claimant', () async {
        final currentBackend = backend!;
        const groupId = 'contract-chord';
        await currentBackend.initGroup(
          GroupDescriptor(
            id: groupId,
            expected: 1,
            ttl: settings.groupTtl,
            meta: const {},
          ),
        );

        final first = await currentBackend.claimChord(
          groupId,
          callbackTaskId: 'cb-task',
          dispatchedAt: DateTime.now(),
        );
        expect(first, isTrue);

        final second = await currentBackend.claimChord(groupId);
        expect(second, isFalse);

        final status = await currentBackend.getGroup(groupId);
        expect(status?.meta[ChordMetadata.callbackTaskId], 'cb-task');
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

      if (encoder is _Base64ContractEncoder) {
        test('custom encoder round-trips binary payloads', () async {
          final currentBackend = backend!;
          final bytes = Uint8List.fromList([1, 2, 3, 4]);
          await currentBackend.set(
            'binary-task',
            TaskState.succeeded,
            payload: bytes,
            attempt: 0,
            meta: _metaWithEncoder(encoder, const {}),
          );
          final status = await currentBackend.get('binary-task');
          expect(status?.payload, bytes);
        });
      }

      test('encoder metadata survives status and group storage', () async {
        final currentBackend = backend!;
        const taskId = 'encoder-meta-task';
        final meta = _metaWithEncoder(encoder, const {'origin': 'meta-test'});
        await currentBackend.set(
          taskId,
          TaskState.succeeded,
          payload: {'value': 'ok'},
          attempt: 0,
          meta: meta,
        );
        final stored = await currentBackend.get(taskId);
        expect(stored, isNotNull);
        expect(stored!.meta[stemResultEncoderMetaKey], encoder.id);
        expect(stored.meta['origin'], 'meta-test');

        const groupId = 'encoder-meta-group';
        await currentBackend.initGroup(
          GroupDescriptor(id: groupId, expected: 1),
        );
        final child = TaskStatus(
          id: 'child-meta',
          state: TaskState.succeeded,
          payload: 'done',
          attempt: 0,
          meta: meta,
        );
        final groupStatus = await currentBackend.addGroupResult(groupId, child);
        expect(groupStatus, isNotNull);
        final resultMeta = groupStatus!.results['child-meta']?.meta;
        expect(resultMeta?[stemResultEncoderMetaKey], encoder.id);
        expect(resultMeta?['origin'], 'meta-test');
      });

      test('group results decode typed payloads via encoders', () async {
        final currentBackend = backend!;
        const groupId = 'typed-encoder-group';
        await currentBackend.initGroup(
          GroupDescriptor(id: groupId, expected: 2),
        );

        Object? payloadFor(int value) {
          if (encoder is _Base64ContractEncoder) {
            return Uint8List.fromList([value]);
          }
          return {'value': value};
        }

        int decodeTyped(Object? payload) {
          if (payload is Uint8List && payload.isNotEmpty) {
            return payload.first;
          }
          if (payload is Map && payload['value'] is num) {
            return (payload['value'] as num).toInt();
          }
          throw StateError('Unexpected payload: $payload');
        }

        Future<GroupStatus?> addChild(String id, int value) {
          final status = TaskStatus(
            id: id,
            state: TaskState.succeeded,
            payload: payloadFor(value),
            attempt: 0,
            meta: _metaWithEncoder(encoder, const {}),
          );
          return currentBackend.addGroupResult(groupId, status);
        }

        final afterFirst = await addChild('child-a', 7);
        expect(afterFirst, isNotNull);
        expect(afterFirst!.isComplete, isFalse);

        final completed = await addChild('child-b', 42);
        expect(completed, isNotNull);
        expect(completed!.isComplete, isTrue);

        final fetched = await currentBackend.getGroup(groupId);
        expect(fetched, isNotNull);
        final values =
            fetched!.results.values
                .map((status) => decodeTyped(status.payload))
                .toList()
              ..sort();
        expect(values, [7, 42]);
        for (final status in fetched.results.values) {
          expect(status.meta[stemResultEncoderMetaKey], encoder.id);
        }
      });
    });
  }
}

ResultBackend _unwrapBackend(ResultBackend backend) {
  var current = backend;
  while (current is EncodingResultBackend) {
    current = current.inner;
  }
  return current;
}

Map<String, Object?> _metaWithEncoder(
  TaskPayloadEncoder encoder,
  Map<String, Object?> meta,
) {
  return {...meta, stemResultEncoderMetaKey: encoder.id};
}

class _Base64ContractEncoder extends TaskPayloadEncoder {
  const _Base64ContractEncoder();

  static const _key = '__b64payload';

  @override
  Object? encode(Object? value) {
    if (value is Uint8List) {
      return {_key: base64Encode(value)};
    }
    return value;
  }

  @override
  Object? decode(Object? stored) {
    if (stored is Map && stored.containsKey(_key)) {
      final encoded = stored[_key];
      if (encoded is String) {
        return Uint8List.fromList(base64Decode(encoded));
      }
    }
    return stored;
  }
}
