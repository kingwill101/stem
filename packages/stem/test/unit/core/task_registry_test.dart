import 'dart:async';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

class _TestHandler implements TaskHandler<void> {
  _TestHandler(this.name, {this.description});

  @override
  final String name;

  final String? description;

  @override
  TaskOptions get options => const TaskOptions();

  @override
  TaskMetadata get metadata => description == null
      ? const TaskMetadata()
      : TaskMetadata(description: description);

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {}
}

class _DuplicateHandler extends _TestHandler {
  _DuplicateHandler(super.name);
}

class _FakeBroker implements Broker {
  Envelope? lastEnvelope;
  RoutingInfo? lastRouting;

  @override
  Future<void> publish(Envelope envelope, {RoutingInfo? routing}) async {
    lastEnvelope = envelope;
    lastRouting = routing;
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
}

class _Args {
  _Args(this.value);
  final int value;
}

void main() {
  group('SimpleTaskRegistry', () {
    test('emits registration events', () async {
      final registry = SimpleTaskRegistry();
      final events = <TaskRegistrationEvent>[];
      final sub = registry.onRegister.listen(events.add);

      final first = _TestHandler('sample.task');
      final second = _TestHandler('sample.task');

      registry.register(first);
      registry.register(second, overrideExisting: true);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(events, hasLength(2));
      expect(events.first.name, 'sample.task');
      expect(events.first.overridden, isFalse);
      expect(events.last.overridden, isTrue);
      expect(events.last.handler, same(second));
    });
    test('throws when registering duplicate handler without override', () {
      final registry = SimpleTaskRegistry();
      registry.register(_DuplicateHandler('sample.task'));

      expect(
        () => registry.register(_DuplicateHandler('sample.task')),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('sample.task'),
          ),
        ),
      );
    });

    test('allows overriding when requested explicitly', () {
      final registry = SimpleTaskRegistry();
      final original = _TestHandler('sample.task');
      final replacement = _TestHandler('sample.task');

      registry.register(original);
      registry.register(replacement, overrideExisting: true);

      expect(registry.resolve('sample.task'), same(replacement));
    });

    test('exposes registered handlers as read-only list', () {
      final registry = SimpleTaskRegistry();
      registry
        ..register(_TestHandler('first'))
        ..register(_TestHandler('second'));

      final handlers = registry.handlers;
      expect(handlers.length, 2);
      expect(handlers.map((h) => h.name), containsAll(['first', 'second']));

      expect(
        () => (handlers as List<TaskHandler>).add(_TestHandler('third')),
        throwsUnsupportedError,
      );
    });

    test('provides default metadata', () {
      final handler = _TestHandler('meta-free');
      expect(handler.metadata.description, isNull);
      expect(handler.metadata.tags, isEmpty);
      expect(handler.metadata.idempotent, isFalse);
    });

    test('allows custom metadata overrides', () {
      final handler = _TestHandler('meta', description: 'Example task');
      expect(handler.metadata.description, 'Example task');
    });
  });

  group('TaskDefinition', () {
    test('encodes arguments using custom encoder', () {
      final definition = TaskDefinition<_Args, void>(
        name: 'demo.task',
        encodeArgs: (args) => {'value': args.value},
      );

      final call = definition(_Args(42));
      expect(call.name, 'demo.task');
      expect(call.encodeArgs(), {'value': 42});
      expect(call.resolveOptions(), const TaskOptions());
    });

    test('enqueues via Stem.enqueueCall', () async {
      final broker = _FakeBroker();
      final registry = SimpleTaskRegistry()
        ..register(_TestHandler('demo.task'));
      final stem = Stem(broker: broker, registry: registry);

      final definition = TaskDefinition<_Args, void>(
        name: 'demo.task',
        encodeArgs: (args) => {'value': args.value},
      );

      final call = definition(
        _Args(99),
        headers: {'x-id': 'abc'},
        options: const TaskOptions(queue: 'custom'),
        meta: const {'source': 'test'},
      );

      final id = await stem.enqueueCall(call);
      expect(id, isNotEmpty);
      expect(broker.lastEnvelope, isNotNull);
      expect(broker.lastEnvelope!.name, 'demo.task');
      expect(broker.lastEnvelope!.args, {'value': 99});
      expect(broker.lastEnvelope!.headers['x-id'], 'abc');
      expect(broker.lastEnvelope!.queue, 'custom');
      expect(broker.lastEnvelope!.meta, containsPair('source', 'test'));
    });
  });

  group('TaskEnqueueBuilder', () {
    test('builds TaskCall with overrides', () {
      final definition = TaskDefinition<_Args, void>(
        name: 'demo.task',
        encodeArgs: (args) => {'value': args.value},
      );

      final builder =
          TaskEnqueueBuilder<_Args, void>(
              definition: definition,
              args: _Args(7),
            )
            ..header('x-id', 'abc')
            ..meta('source', 'test')
            ..priority(5)
            ..queue('fast')
            ..delay(const Duration(seconds: 1));

      final call = builder.build();
      expect(call.headers['x-id'], 'abc');
      expect(call.meta['source'], 'test');
      expect(call.resolveOptions().priority, 5);
      expect(call.resolveOptions().queue, 'fast');
      expect(call.notBefore, isNotNull);
      expect(call.encodeArgs(), {'value': 7});
    });
  });
}
