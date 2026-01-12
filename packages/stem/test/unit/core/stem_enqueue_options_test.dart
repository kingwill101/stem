import 'dart:async';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

const _expiresAtKey = 'stem.expiresAt';
const _timeLimitMsKey = 'stem.timeLimitMs';
const _softTimeLimitMsKey = 'stem.softTimeLimitMs';
const _shadowKey = 'stem.shadow';
const _replyToKey = 'stem.replyTo';
const _serializerKey = 'stem.serializer';
const _compressionKey = 'stem.compression';
const _ignoreResultKey = 'stem.ignoreResult';

void main() {
  group('Stem.enqueue options', () {
    test('applies countdown to notBefore', () async {
      final broker = _RecordingBroker();
      final registry = SimpleTaskRegistry()..register(_StubTaskHandler());
      final stem = Stem(broker: broker, registry: registry);

      final start = DateTime.now();
      await stem.enqueue(
        'tasks.stub',
        enqueueOptions: const TaskEnqueueOptions(
          countdown: Duration(milliseconds: 200),
        ),
      );

      final record = broker.published.single;
      expect(record.envelope.notBefore, isNotNull);
      final notBefore = record.envelope.notBefore!;
      expect(
        notBefore.isAfter(start.add(const Duration(milliseconds: 150))),
        isTrue,
      );
    });

    test('applies eta to notBefore', () async {
      final broker = _RecordingBroker();
      final registry = SimpleTaskRegistry()..register(_StubTaskHandler());
      final stem = Stem(broker: broker, registry: registry);

      final eta = DateTime.utc(2026, 01, 03, 12, 30);
      await stem.enqueue(
        'tasks.stub',
        enqueueOptions: TaskEnqueueOptions(eta: eta),
      );

      final record = broker.published.single;
      expect(record.envelope.notBefore, equals(eta));
    });

    test('applies taskId override', () async {
      final broker = _RecordingBroker();
      final registry = SimpleTaskRegistry()..register(_StubTaskHandler());
      final stem = Stem(broker: broker, registry: registry);

      await stem.enqueue(
        'tasks.stub',
        enqueueOptions: const TaskEnqueueOptions(taskId: 'custom-task-id'),
      );

      final record = broker.published.single;
      expect(record.envelope.id, equals('custom-task-id'));
    });

    test('propagates routing overrides', () async {
      final broker = _RecordingBroker();
      final registry = SimpleTaskRegistry()..register(_StubTaskHandler());
      final stem = Stem(broker: broker, registry: registry);

      await stem.enqueue(
        'tasks.stub',
        enqueueOptions: const TaskEnqueueOptions(
          queue: 'critical',
          exchange: 'billing',
          routingKey: 'invoices',
          priority: 7,
        ),
      );

      final record = broker.published.single;
      expect(record.envelope.queue, equals('critical'));
      expect(record.routing?.queue, equals('critical'));
      expect(record.routing?.exchange, equals('billing'));
      expect(record.routing?.routingKey, equals('invoices'));
      expect(record.routing?.priority, equals(7));
    });

    test('stores metadata options in envelope meta', () async {
      final broker = _RecordingBroker();
      final registry = SimpleTaskRegistry()..register(_StubTaskHandler());
      final stem = Stem(broker: broker, registry: registry);

      await stem.enqueue(
        'tasks.stub',
        enqueueOptions: TaskEnqueueOptions(
          expires: DateTime.utc(2026, 01, 03, 12, 45),
          timeLimit: const Duration(seconds: 30),
          softTimeLimit: const Duration(seconds: 10),
          shadow: 'shadow.name',
          replyTo: 'reply.queue',
          serializer: 'json',
          compression: 'gzip',
          ignoreResult: true,
        ),
      );

      final meta = broker.published.single.envelope.meta;
      expect(meta[_expiresAtKey], equals('2026-01-03T12:45:00.000Z'));
      expect(meta[_timeLimitMsKey], equals(30000));
      expect(meta[_softTimeLimitMsKey], equals(10000));
      expect(meta[_shadowKey], equals('shadow.name'));
      expect(meta[_replyToKey], equals('reply.queue'));
      expect(meta[_serializerKey], equals('json'));
      expect(meta[_compressionKey], equals('gzip'));
      expect(meta[_ignoreResultKey], isTrue);
    });

    test('retries publish when retry enabled', () async {
      final broker = _FlakyPublishBroker(failures: 1);
      final registry = SimpleTaskRegistry()..register(_StubTaskHandler());
      final stem = Stem(broker: broker, registry: registry);

      await stem.enqueue(
        'tasks.stub',
        enqueueOptions: const TaskEnqueueOptions(
          retry: true,
          retryPolicy: TaskRetryPolicy(),
        ),
      );

      expect(broker.attempts, equals(2));
    });
  });
}

class _StubTaskHandler implements TaskHandler<void> {
  @override
  String get name => 'tasks.stub';

  @override
  TaskOptions get options => const TaskOptions();

  @override
  TaskMetadata get metadata => const TaskMetadata();

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {}
}

class _PublishedRecord {
  const _PublishedRecord(this.envelope, this.routing);

  final Envelope envelope;
  final RoutingInfo? routing;
}

class _RecordingBroker implements Broker {
  final List<_PublishedRecord> published = [];

  @override
  Future<void> publish(Envelope envelope, {RoutingInfo? routing}) async {
    published.add(_PublishedRecord(envelope, routing));
  }

  @override
  Stream<Delivery> consume(
    RoutingSubscription subscription, {
    int prefetch = 1,
    String? consumerGroup,
    String? consumerName,
  }) => const Stream.empty();

  @override
  Future<void> ack(Delivery delivery) async {}

  @override
  Future<void> deadLetter(
    Delivery delivery, {
    String? reason,
    Map<String, Object?>? meta,
  }) async {}

  @override
  Future<void> extendLease(Delivery delivery, Duration by) async {}

  @override
  Future<int?> inflightCount(String queue) async => 0;

  @override
  Future<DeadLetterEntry?> getDeadLetter(String queue, String id) async => null;

  @override
  Future<DeadLetterPage> listDeadLetters(
    String queue, {
    int limit = 50,
    int offset = 0,
  }) async => const DeadLetterPage(entries: []);

  @override
  Future<void> nack(Delivery delivery, {bool requeue = true}) async {}

  @override
  Future<int?> pendingCount(String queue) async => 0;

  @override
  Future<void> purge(String queue) async {}

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
  bool get supportsDelayed => true;

  @override
  bool get supportsPriority => true;

  @override
  Future<void> close() async {}
}

class _FlakyPublishBroker extends _RecordingBroker {
  _FlakyPublishBroker({required this.failures});

  final int failures;
  int attempts = 0;

  @override
  Future<void> publish(Envelope envelope, {RoutingInfo? routing}) async {
    attempts += 1;
    if (attempts <= failures) {
      throw StateError('publish failed');
    }
    await super.publish(envelope, routing: routing);
  }
}
