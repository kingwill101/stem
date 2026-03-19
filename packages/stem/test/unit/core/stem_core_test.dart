import 'dart:async';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('Envelope', () {
    test('round trips through json', () {
      final envelope = Envelope(
        id: 'abc',
        name: 'example',
        args: {'value': 42},
        headers: {'trace-id': '123'},
        notBefore: DateTime.utc(2024, 01, 02, 03, 04, 05),
        priority: 3,
        attempt: 2,
        maxRetries: 5,
        visibilityTimeout: const Duration(seconds: 30),
        queue: 'emails',
        meta: {'foo': 'bar'},
      );

      final json = envelope.toJson();
      final copy = Envelope.fromJson(json);

      expect(copy.id, equals(envelope.id));
      expect(copy.name, equals(envelope.name));
      expect(copy.args, equals({'value': 42}));
      expect(copy.headers, equals({'trace-id': '123'}));
      expect(copy.notBefore, equals(envelope.notBefore));
      expect(copy.priority, equals(3));
      expect(copy.attempt, equals(2));
      expect(copy.maxRetries, equals(5));
      expect(copy.visibilityTimeout, equals(const Duration(seconds: 30)));
      expect(copy.queue, equals('emails'));
      expect(copy.meta, equals({'foo': 'bar'}));
    });
  });

  group('StemConfig', () {
    test('reads from environment with defaults', () {
      final config = StemConfig.fromEnvironment({
        'STEM_BROKER_URL': 'redis://localhost:6379',
        'STEM_DEFAULT_MAX_RETRIES': '7',
      });

      expect(config.brokerUrl, equals('redis://localhost:6379'));
      expect(config.defaultQueue, equals('default'));
      expect(config.defaultMaxRetries, equals(7));
      expect(config.prefetchMultiplier, equals(2));
      expect(config.resultBackendUrl, isNull);
    });

    test('throws when broker url missing', () {
      expect(() => StemConfig.fromEnvironment({}), throwsStateError);
    });
  });

  group('Stem.enqueue', () {
    test('publishes to broker and writes queued state', () async {
      final broker = _RecordingBroker();
      final backend = _RecordingBackend();
      final stem = Stem(
        broker: broker,
        backend: backend,
        tasks: [_StubTaskHandler()],
      );

      final id = await stem.enqueue(
        'sample.task',
        args: {'value': 'ok'},
        options: const TaskOptions(queue: 'custom', maxRetries: 4),
      );

      expect(broker.published.single.envelope.id, equals(id));
      expect(broker.published.single.envelope.queue, equals('custom'));
      expect(backend.records.single.id, equals(id));
      expect(backend.records.single.state, equals(TaskState.queued));
    });

    test(
      'enqueueCall publishes typed calls without requiring registry handlers',
      () async {
        final broker = _RecordingBroker();
        final backend = _RecordingBackend();
        final stem = Stem(broker: broker, backend: backend);
        final definition = TaskDefinition<({String value}), Object?>(
          name: 'sample.typed',
          encodeArgs: (args) => {'value': args.value},
          defaultOptions: const TaskOptions(queue: 'typed'),
        );

        final id = await stem.enqueueCall(definition.call((value: 'ok')));

        expect(id, isNotEmpty);
        expect(broker.published.single.envelope.name, 'sample.typed');
        expect(broker.published.single.envelope.queue, 'typed');
        expect(backend.records.single.id, id);
        expect(backend.records.single.state, TaskState.queued);
      },
    );

    test(
      'enqueueCall uses definition encoder metadata on producer-only paths',
      () async {
        final broker = _RecordingBroker();
        final backend = _RecordingBackend();
        final stem = Stem(
          broker: broker,
          backend: backend,
          encoderRegistry: ensureTaskPayloadEncoderRegistry(
            null,
            additionalEncoders: [_codecReceiptEncoder, _passthroughMapEncoder],
          ),
        );
        final definition = TaskDefinition<({String value}), _CodecReceipt>(
          name: 'sample.typed.encoded',
          encodeArgs: (args) => {'value': args.value},
          metadata: const TaskMetadata(
            argsEncoder: _passthroughMapEncoder,
            resultEncoder: _codecReceiptEncoder,
          ),
        );

        final id = await stem.enqueueCall(
          definition.call((value: 'encoded')),
        );

        expect(
          broker.published.single.envelope.headers[stemArgsEncoderHeader],
          _passthroughMapEncoder.id,
        );
        expect(
          backend.records.single.meta[stemResultEncoderMetaKey],
          _codecReceiptEncoder.id,
        );
        expect(backend.records.single.id, id);
      },
    );

    test(
      'enqueueCall publishes no-arg definitions without fake empty maps',
      () async {
        final broker = _RecordingBroker();
        final backend = _RecordingBackend();
        final stem = Stem(broker: broker, backend: backend);
        final definition = TaskDefinition.noArgs<String>(
          name: 'sample.no_args',
          defaultOptions: const TaskOptions(queue: 'typed'),
        );

        final id = await definition.enqueueWith(stem);

        expect(id, isNotEmpty);
        expect(broker.published.single.envelope.name, 'sample.no_args');
        expect(broker.published.single.envelope.queue, 'typed');
        expect(broker.published.single.envelope.args, isEmpty);
        expect(backend.records.single.id, id);
        expect(backend.records.single.state, TaskState.queued);
      },
    );
  });

  group('TaskCall helpers', () {
    test('enqueueWith enqueues typed calls with scoped metadata', () async {
      final broker = _RecordingBroker();
      final backend = _RecordingBackend();
      final stem = Stem(broker: broker, backend: backend);
      final definition = TaskDefinition<({String value}), String>(
        name: 'sample.task_call',
        encodeArgs: (args) => {'value': args.value},
        defaultOptions: const TaskOptions(queue: 'typed'),
      );

      final taskId = await TaskEnqueueScope.run({'traceId': 'scope-1'}, () {
        return definition.call((value: 'ok')).enqueueWith(stem);
      });

      expect(taskId, isNotEmpty);
      expect(broker.published.single.envelope.name, 'sample.task_call');
      expect(broker.published.single.envelope.queue, 'typed');
      expect(
        broker.published.single.envelope.meta,
        containsPair('traceId', 'scope-1'),
      );
    });

    test('enqueueAndWaitWith returns typed results', () async {
      final broker = _RecordingBroker();
      final backend = _RecordingBackend();
      final stem = Stem(broker: broker, backend: backend);
      final definition = TaskDefinition<({String value}), String>(
        name: 'sample.task_call_wait',
        encodeArgs: (args) => {'value': args.value},
      );

      unawaited(
        Future<void>(() async {
          while (broker.published.isEmpty) {
            await Future<void>.delayed(Duration.zero);
          }
          final taskId = broker.published.single.envelope.id;
          await backend.set(taskId, TaskState.succeeded, payload: 'done');
        }),
      );

      final result = await definition
          .call((value: 'ok'))
          .enqueueAndWaitWith(stem, timeout: const Duration(seconds: 1));

      expect(result?.isSucceeded, isTrue);
      expect(result?.value, 'done');
    });
  });

  group('TaskDefinition.waitFor', () {
    test('uses definition decoding rules', () async {
      final backend = _codecAwareBackend();
      final stem = _codecAwareStem(backend);

      await backend.set(
        'task-definition-wait',
        TaskState.succeeded,
        payload: const _CodecReceipt('receipt-definition'),
        meta: {stemResultEncoderMetaKey: _codecReceiptEncoder.id},
      );

      final result = await _codecReceiptDefinition.waitFor(
        stem,
        'task-definition-wait',
      );

      expect(result?.value?.id, 'receipt-definition');
      expect(result?.rawPayload, isA<_CodecReceipt>());
    });

    test('supports no-arg task definitions', () async {
      final backend = InMemoryResultBackend();
      final stem = Stem(broker: _RecordingBroker(), backend: backend);
      final definition = TaskDefinition.noArgs<String>(name: 'no-args.wait');

      await backend.set(
        'task-no-args-wait',
        TaskState.succeeded,
        payload: 'done',
      );

      final result = await definition.waitFor(stem, 'task-no-args-wait');

      expect(result?.value, 'done');
      expect(result?.rawPayload, 'done');
    });

    test('enqueueAndWaitWith supports no-arg task definitions', () async {
      final broker = _RecordingBroker();
      final backend = _RecordingBackend();
      final stem = Stem(broker: broker, backend: backend);
      final definition = TaskDefinition.noArgs<String>(name: 'no-args.enqueue');

      unawaited(
        Future<void>(() async {
          while (broker.published.isEmpty) {
            await Future<void>.delayed(Duration.zero);
          }
          final taskId = broker.published.single.envelope.id;
          await backend.set(taskId, TaskState.succeeded, payload: 'done');
        }),
      );

      final result = await definition.enqueueAndWaitWith(
        stem,
        timeout: const Duration(seconds: 1),
      );

      expect(result?.value, 'done');
      expect(result?.rawPayload, 'done');
    });
  });

  group('Stem.waitForTaskDefinition', () {
    test('does not double decode codec-backed terminal results', () async {
      final backend = _codecAwareBackend();
      final stem = _codecAwareStem(backend);

      await backend.set(
        'task-terminal',
        TaskState.succeeded,
        payload: const _CodecReceipt('receipt-terminal'),
        meta: {stemResultEncoderMetaKey: _codecReceiptEncoder.id},
      );

      final result = await stem.waitForTaskDefinition(
        'task-terminal',
        _codecReceiptDefinition,
      );

      expect(result?.value?.id, 'receipt-terminal');
      expect(result?.rawPayload, isA<_CodecReceipt>());
    });

    test('does not double decode codec-backed watched results', () async {
      final backend = _codecAwareBackend();
      final stem = _codecAwareStem(backend);

      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 20), () async {
          await backend.set(
            'task-watched',
            TaskState.succeeded,
            payload: const _CodecReceipt('receipt-watched'),
            meta: {stemResultEncoderMetaKey: _codecReceiptEncoder.id},
          );
        }),
      );

      final result = await stem.waitForTaskDefinition(
        'task-watched',
        _codecReceiptDefinition,
        timeout: const Duration(seconds: 1),
      );

      expect(result?.value?.id, 'receipt-watched');
      expect(result?.rawPayload, isA<_CodecReceipt>());
    });
  });
}

ResultBackend _codecAwareBackend() {
  final registry = ensureTaskPayloadEncoderRegistry(
    null,
    additionalEncoders: [_codecReceiptEncoder],
  );
  return withTaskPayloadEncoder(InMemoryResultBackend(), registry);
}

Stem _codecAwareStem(ResultBackend backend) {
  return Stem(
    broker: _RecordingBroker(),
    backend: backend,
    encoderRegistry: ensureTaskPayloadEncoderRegistry(
      null,
      additionalEncoders: [_codecReceiptEncoder],
    ),
  );
}

class _CodecReceipt {
  const _CodecReceipt(this.id);

  factory _CodecReceipt.fromJson(Map<String, Object?> json) {
    return _CodecReceipt(json['id']! as String);
  }

  final String id;

  Map<String, Object?> toJson() => {'id': id};
}

const _codecReceiptCodec = PayloadCodec<_CodecReceipt>(
  encode: _encodeCodecReceipt,
  decode: _decodeCodecReceipt,
);

const _codecReceiptEncoder = CodecTaskPayloadEncoder<_CodecReceipt>(
  idValue: 'test.codec.receipt',
  codec: _codecReceiptCodec,
);

const _passthroughMapEncoder = _MapPassthroughEncoder('test.args.map');

final _codecReceiptDefinition =
    TaskDefinition<Map<String, Object?>, _CodecReceipt>(
      name: 'codec.receipt',
      encodeArgs: (args) => args,
      decodeResult: _codecReceiptCodec.decode,
    );

Object? _encodeCodecReceipt(_CodecReceipt value) => value.toJson();

_CodecReceipt _decodeCodecReceipt(Object? payload) {
  return _CodecReceipt.fromJson(Map<String, Object?>.from(payload! as Map));
}

class _StubTaskHandler implements TaskHandler<void> {
  @override
  String get name => 'sample.task';

  @override
  TaskOptions get options => const TaskOptions();

  @override
  TaskMetadata get metadata => const TaskMetadata();

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {}
}

class _RecordingBroker implements Broker {
  final List<Delivery> published = [];

  @override
  Future<void> ack(Delivery delivery) async {}

  @override
  Future<void> deadLetter(
    Delivery delivery, {
    String? reason,
    Map<String, Object?>? meta,
  }) async {}

  @override
  Future<void> nack(Delivery delivery, {bool requeue = true}) async {}

  @override
  Future<void> publish(Envelope envelope, {RoutingInfo? routing}) async {
    published.add(
      Delivery(envelope: envelope, receipt: 'receipt', leaseExpiresAt: null),
    );
  }

  @override
  Future<void> purge(String queue) async {}

  @override
  Stream<Delivery> consume(
    RoutingSubscription subscription, {
    int prefetch = 1,
    String? consumerGroup,
    String? consumerName,
  }) => const Stream.empty();

  @override
  Future<void> extendLease(Delivery delivery, Duration by) async {}

  @override
  Future<int?> pendingCount(String queue) async => published.length;

  @override
  Future<int?> inflightCount(String queue) async => 0;

  @override
  bool get supportsDelayed => true;

  @override
  bool get supportsPriority => false;

  @override
  Future<DeadLetterPage> listDeadLetters(
    String queue, {
    int limit = 50,
    int offset = 0,
  }) async => const DeadLetterPage(entries: []);

  @override
  Future<DeadLetterEntry?> getDeadLetter(String queue, String id) async => null;

  @override
  Future<DeadLetterReplayResult> replayDeadLetters(
    String queue, {
    int limit = 50,
    DateTime? since,
    Duration? delay,
    bool dryRun = false,
  }) async => DeadLetterReplayResult(entries: const [], dryRun: dryRun);

  @override
  Future<int> purgeDeadLetters(
    String queue, {
    DateTime? since,
    int? limit,
  }) async => 0;

  @override
  Future<void> close() async {}
}

class _MapPassthroughEncoder implements TaskPayloadEncoder {
  const _MapPassthroughEncoder(this.id);

  @override
  final String id;

  @override
  Object? encode(Object? value) => value;

  @override
  Object? decode(Object? value) => value;
}

class _RecordingBackend implements ResultBackend {
  final List<TaskStatus> records = [];
  final Map<String, StreamController<TaskStatus>> _controllers = {};
  final Map<String, GroupStatus> _groups = {};
  WorkerHeartbeat? lastHeartbeat;
  final Set<String> _claimedChords = {};

  @override
  Future<TaskStatus?> get(String taskId) async => records
      .cast<TaskStatus?>()
      .firstWhere((e) => e?.id == taskId, orElse: () => null);

  @override
  Stream<TaskStatus> watch(String taskId) {
    final controller = _controllers.putIfAbsent(
      taskId,
      StreamController<TaskStatus>.broadcast,
    );
    return controller.stream;
  }

  @override
  Future<TaskStatusPage> listTaskStatuses(
    TaskStatusListRequest request,
  ) async {
    return const TaskStatusPage(items: []);
  }

  @override
  Future<void> set(
    String taskId,
    TaskState state, {
    Object? payload,
    TaskError? error,
    int attempt = 0,
    Map<String, Object?> meta = const {},
    Duration? ttl,
  }) async {
    records.add(
      TaskStatus(
        id: taskId,
        state: state,
        payload: payload,
        error: error,
        attempt: attempt,
        meta: meta,
      ),
    );
    _controllers[taskId]?.add(records.last);
  }

  @override
  Future<void> initGroup(GroupDescriptor descriptor) async {
    _groups[descriptor.id] = GroupStatus(
      id: descriptor.id,
      expected: descriptor.expected,
      meta: descriptor.meta,
    );
  }

  @override
  Future<void> setWorkerHeartbeat(WorkerHeartbeat heartbeat) async {
    lastHeartbeat = heartbeat;
  }

  @override
  Future<WorkerHeartbeat?> getWorkerHeartbeat(String workerId) async {
    return lastHeartbeat?.workerId == workerId ? lastHeartbeat : null;
  }

  @override
  Future<List<WorkerHeartbeat>> listWorkerHeartbeats() async {
    return lastHeartbeat == null ? const [] : [lastHeartbeat!];
  }

  @override
  Future<GroupStatus?> addGroupResult(String groupId, TaskStatus status) async {
    final existing = _groups[groupId];
    if (existing == null) return null;
    final updatedResults = Map<String, TaskStatus>.from(existing.results)
      ..[status.id] = status;
    final updated = GroupStatus(
      id: existing.id,
      expected: existing.expected,
      results: updatedResults,
      meta: existing.meta,
    );
    _groups[groupId] = updated;
    return updated;
  }

  @override
  Future<GroupStatus?> getGroup(String groupId) async => _groups[groupId];

  @override
  Future<bool> claimChord(
    String groupId, {
    String? callbackTaskId,
    DateTime? dispatchedAt,
  }) async {
    final added = _claimedChords.add(groupId);
    if (!added) return false;
    final existing = _groups[groupId];
    if (existing != null) {
      final meta = Map<String, Object?>.from(existing.meta);
      if (callbackTaskId != null) {
        meta[ChordMetadata.callbackTaskId] = callbackTaskId;
      }
      if (dispatchedAt != null) {
        meta[ChordMetadata.dispatchedAt] = dispatchedAt.toIso8601String();
      }
      _groups[groupId] = GroupStatus(
        id: existing.id,
        expected: existing.expected,
        results: existing.results,
        meta: meta,
      );
    }
    return true;
  }

  @override
  Future<void> expire(String taskId, Duration ttl) async {}

  @override
  Future<void> close() async {}
}
