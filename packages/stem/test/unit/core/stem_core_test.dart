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
      final registry = SimpleTaskRegistry()..register(_StubTaskHandler());

      final stem = Stem(broker: broker, registry: registry, backend: backend);

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
  });
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
}
