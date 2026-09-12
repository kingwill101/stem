import 'package:stem/memory.dart';
import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  test(
    'failed terminal hook is recovered once on grouped redelivery',
    () async {
      final broker = InMemoryBroker();
      final backend = InMemoryResultBackend();
      final task = _HookFailsOnceTask();
      const groupId = 'group-hook';
      await backend.initGroup(GroupDescriptor(id: groupId, expected: 1));
      final envelope = Envelope(
        name: task.name,
        args: const {},
        headers: {'stem-group-id': groupId},
      );
      Worker worker() => Worker(
        broker: broker,
        backend: backend,
        tasks: [task],
        concurrency: 1,
      );
      addTearDown(broker.dispose);

      await broker.publish(envelope);
      final first = await worker().runUntilIdle(
        budget: const Duration(seconds: 1),
        shutdownReserve: const Duration(milliseconds: 100),
        idleTimeout: const Duration(milliseconds: 10),
      );
      expect(first.reason, WorkerRunStopReason.failed);
      expect(task.calls, 1);
      expect(task.finalizations, 1);
      expect((await backend.getGroup(groupId))!.results, isEmpty);

      await broker.publish(envelope);
      await worker().runUntilIdle(
        budget: const Duration(seconds: 1),
        shutdownReserve: const Duration(milliseconds: 100),
        idleTimeout: const Duration(milliseconds: 10),
      );
      final group = await backend.getGroup(groupId);
      expect(task.calls, 1);
      expect(task.finalizations, 2);
      expect(group!.results, hasLength(1));
    },
  );

  test(
    'exhausted explicit retry finalizes grouped task once on redelivery',
    () async {
      final broker = InMemoryBroker();
      final backend = InMemoryResultBackend();
      final task = _ExplicitRetryTask();
      const groupId = 'group-explicit';
      var failedSignals = 0;
      final signalSubscription = StemSignals.taskFailed.connect((payload, _) {
        if (payload.taskName == task.name) failedSignals++;
      });
      addTearDown(signalSubscription.cancel);
      await backend.initGroup(GroupDescriptor(id: groupId, expected: 1));
      final envelope = Envelope(
        name: task.name,
        args: const {},
        headers: const {'stem-group-id': groupId},
      );
      Worker worker() => Worker(
        broker: broker,
        backend: backend,
        tasks: [task],
        concurrency: 1,
      );
      addTearDown(broker.dispose);

      await broker.publish(envelope);
      await worker().runUntilIdle(
        budget: const Duration(seconds: 1),
        shutdownReserve: const Duration(milliseconds: 100),
        idleTimeout: const Duration(milliseconds: 10),
      );
      await broker.publish(envelope);
      await worker().runUntilIdle(
        budget: const Duration(seconds: 1),
        shutdownReserve: const Duration(milliseconds: 100),
        idleTimeout: const Duration(milliseconds: 10),
      );

      final group = await backend.getGroup(groupId);
      expect(task.calls, 1);
      expect(task.finalizations, 1);
      expect(failedSignals, 1);
      expect(group!.results, hasLength(1));
      expect(
        (await backend.get(envelope.id))!.meta['stem.terminalFailureEnvelope'],
        isA<Map<Object?, Object?>>(),
      );
    },
  );

  test(
    'failed linked publication retains lease until recovered dispatch',
    () async {
      final broker = _LinkPublicationBroker();
      final backend = InMemoryResultBackend();
      addTearDown(broker.close);
      addTearDown(backend.close);
      final task = _ExplicitRetryTask();
      final registry = InMemoryTaskRegistry()
        ..register(task)
        ..register(
          FunctionTaskHandler<void>.inline(
            name: 'recovery.link',
            entrypoint: (context, args) async => null,
          ),
        );
      final producer = Stem(
        broker: broker,
        backend: backend,
        registry: registry,
      );
      const groupId = 'group-linked';
      await backend.initGroup(GroupDescriptor(id: groupId, expected: 1));
      final envelope = Envelope(
        name: task.name,
        args: const {},
        headers: const {'stem-group-id': groupId},
        meta: const {
          'stem.linkError': [
            {
              'name': 'recovery.link',
              'options': {'queue': 'links'},
            },
          ],
        },
      );
      Future<WorkerRunOutcome> drain() =>
          Worker(
            broker: broker,
            backend: backend,
            registry: registry,
            enqueuer: producer,
            concurrency: 1,
            lifecycle: const WorkerLifecycleConfig(
              installSignalHandlers: false,
            ),
          ).runUntilIdle(
            budget: const Duration(seconds: 4),
            shutdownReserve: Duration.zero,
            idleTimeout: const Duration(seconds: 2),
          );
      await broker.publish(envelope);
      expect((await drain()).reason, WorkerRunStopReason.failed);
      expect(broker.settlements, 0);
      expect(await broker.inflightCount('default'), 1);
      expect(broker.linkPublications, 0);

      broker.rejectLink = false;
      // No fabricated duplicate: let the still-owned delivery's lease expire.
      await drain();
      expect(task.calls, 1);
      expect(broker.linkPublications, 1);
      expect(broker.settlements, 1);
      expect((await backend.getGroup(groupId))!.results, hasLength(1));

      final finalized = task.finalizations;
      await broker.publish(envelope);
      await drain();
      expect(task.calls, 1);
      expect(task.finalizations, finalized);
      expect(broker.linkPublications, 1);
    },
  );
}

class _LinkPublicationBroker extends InMemoryBroker {
  _LinkPublicationBroker()
    : super(
        defaultVisibilityTimeout: const Duration(seconds: 1),
        claimInterval: const Duration(milliseconds: 20),
      );

  bool rejectLink = true;
  int linkPublications = 0;
  int settlements = 0;

  @override
  Future<void> publish(Envelope envelope, {RoutingInfo? routing}) async {
    if (envelope.name == 'recovery.link') {
      if (rejectLink) throw StateError('linked publication unavailable');
      linkPublications++;
    }
    await super.publish(envelope, routing: routing);
  }

  @override
  Future<void> nack(Delivery delivery, {bool requeue = true}) async {
    if (!requeue) settlements++;
    await super.nack(delivery, requeue: requeue);
  }

  @override
  Future<void> ack(Delivery delivery) async {
    settlements++;
    await super.ack(delivery);
  }
}

class _HookFailsOnceTask
    implements TaskHandler<void>, TaskTerminalFailureHandler {
  int calls = 0;
  int finalizations = 0;

  @override
  String get name => 'recovery.hook';
  @override
  TaskOptions get options => const TaskOptions();
  @override
  TaskMetadata get metadata => const TaskMetadata();
  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    calls++;
    throw StateError('handler failure');
  }

  @override
  Future<void> onTerminalFailure(Envelope envelope, TaskStatus status) async {
    finalizations++;
    if (finalizations == 1) throw StateError('hook failure');
  }
}

class _ExplicitRetryTask
    implements TaskHandler<void>, TaskTerminalFailureHandler {
  int calls = 0;
  int finalizations = 0;

  @override
  String get name => 'recovery.explicit';
  @override
  TaskOptions get options => const TaskOptions();
  @override
  TaskMetadata get metadata => const TaskMetadata();
  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    calls++;
    throw TaskRetryRequest(maxRetries: 0);
  }

  @override
  Future<void> onTerminalFailure(Envelope envelope, TaskStatus status) async {
    finalizations++;
  }
}
