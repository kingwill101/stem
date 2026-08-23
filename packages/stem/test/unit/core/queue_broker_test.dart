import 'package:stem/memory.dart';
import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  test(
    'a queue-only transport can run Stem without optional broker APIs',
    () async {
      final broker = _QueueOnlyBroker();
      expect(broker.capabilities.supportsLeaseExtension, isFalse);
      expect(
        broker.capabilities.deliveryGuarantee,
        BrokerDeliveryGuarantee.unknown,
      );
      expect(broker.capabilities.supportsDeadLetterReplay, isFalse);
      final backend = InMemoryResultBackend();
      final task = FunctionTaskHandler<String>.inline(
        name: 'queue-only.echo',
        entrypoint: (context, args) async => 'ok',
      );
      final worker = Worker(
        broker: broker,
        backend: backend,
        tasks: [task],
        consumerName: 'queue-only-worker',
        concurrency: 1,
        prefetchMultiplier: 1,
        lifecycle: const WorkerLifecycleConfig(installSignalHandlers: false),
      );

      await worker.start();
      try {
        final producer = Stem(
          broker: broker,
          backend: backend,
          tasks: [task],
        );
        final taskId = await producer.enqueue(task.name);
        final status = await backend
            .watch(taskId)
            .firstWhere(
              (value) => value.state == TaskState.succeeded,
            );

        expect(status.payload, 'ok');
      } finally {
        await worker.shutdown();
        await broker.close();
        await backend.close();
      }
    },
  );

  test(
    'queue-only failures are terminal without dead-letter support',
    () async {
      final broker = _QueueOnlyBroker();
      final backend = InMemoryResultBackend();
      final task = FunctionTaskHandler<String>.inline(
        name: 'queue-only.failure',
        entrypoint: (context, args) async {
          throw StateError('expected failure');
        },
      );
      final worker = Worker(
        broker: broker,
        backend: backend,
        tasks: [task],
        consumerName: 'queue-only-failure-worker',
        concurrency: 1,
        prefetchMultiplier: 1,
        lifecycle: const WorkerLifecycleConfig(installSignalHandlers: false),
      );

      await worker.start();
      try {
        final producer = Stem(
          broker: broker,
          backend: backend,
          tasks: [task],
        );
        final taskId = await producer.enqueue(task.name);
        final status = await backend
            .watch(taskId)
            .firstWhere(
              (value) => value.state == TaskState.failed,
            );

        expect(status.error?.message, contains('expected failure'));
      } finally {
        await worker.shutdown();
        await broker.close();
        await backend.close();
      }
    },
  );
}

/// Deliberately implements only [QueueBroker], not the compatibility [Broker]
/// facade or any optional capability interface.
final class _QueueOnlyBroker implements QueueBroker {
  _QueueOnlyBroker() : _delegate = InMemoryBroker();

  final InMemoryBroker _delegate;

  @override
  Future<void> publish(Envelope envelope, {RoutingInfo? routing}) =>
      _delegate.publish(envelope, routing: routing);

  @override
  Stream<Delivery> consume(
    RoutingSubscription subscription, {
    int prefetch = 1,
    String? consumerGroup,
    String? consumerName,
  }) => _delegate.consume(
    subscription,
    prefetch: prefetch,
    consumerGroup: consumerGroup,
    consumerName: consumerName,
  );

  @override
  Future<void> ack(Delivery delivery) => _delegate.ack(delivery);

  @override
  Future<void> nack(Delivery delivery, {bool requeue = true}) =>
      _delegate.nack(delivery, requeue: requeue);

  @override
  Future<void> close() => _delegate.close();
}
