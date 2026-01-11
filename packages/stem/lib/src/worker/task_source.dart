import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/envelope.dart';

/// Abstract source of task deliveries for workers.
abstract class TaskSource {
  /// Consumes task deliveries from the given subscription.
  Stream<Delivery> consume(
    RoutingSubscription subscription, {
    int? prefetch,
    String? consumerName,
  });

  /// Acknowledges successful processing of a delivery.
  Future<void> ack(Delivery delivery);

  /// Negatively acknowledges a delivery, optionally requeueing it.
  Future<void> nack(Delivery delivery, {bool requeue = true});

  /// Extends the lease for a delivery by the given duration.
  Future<void> extendLease(Delivery delivery, Duration duration);

  /// Sends a delivery to the dead letter queue.
  Future<void> deadLetter(
    Delivery delivery, {
    String? reason,
    Map<String, Object?>? meta,
  });

  /// Returns the number of pending tasks in the queue, if supported.
  Future<int?> pendingCount(String queue);

  /// Publishes an envelope back to the broker.
  Future<void> publish(Envelope envelope);
}

/// A task enqueuer that throws when invoked, used as a placeholder.
class NoopTaskEnqueuer implements TaskEnqueuer {
  /// Creates a no-op enqueuer.
  const NoopTaskEnqueuer();

  @override
  Future<String> enqueue(
    String name, {
    Map<String, Object?> args = const {},
    Map<String, String> headers = const {},
    TaskOptions options = const TaskOptions(),
    Map<String, Object?> meta = const {},
    TaskEnqueueOptions? enqueueOptions,
  }) {
    throw UnsupportedError('No task enqueuer configured for this worker');
  }

  @override
  Future<String> enqueueCall<TArgs, TResult>(
    TaskCall<TArgs, TResult> call, {
    TaskEnqueueOptions? enqueueOptions,
  }) {
    throw UnsupportedError('No task enqueuer configured for this worker');
  }
}

/// Task source backed by a broker implementation.
class BrokerTaskSource implements TaskSource {
  /// Creates a broker-backed task source.
  BrokerTaskSource(this._broker);

  final Broker _broker;

  @override
  Stream<Delivery> consume(
    RoutingSubscription subscription, {
    int? prefetch,
    String? consumerName,
  }) => _broker.consume(
    subscription,
    prefetch: prefetch ?? 1,
    consumerName: consumerName,
  );

  @override
  Future<void> ack(Delivery delivery) => _broker.ack(delivery);

  @override
  Future<void> nack(Delivery delivery, {bool requeue = true}) =>
      _broker.nack(delivery, requeue: requeue);

  @override
  Future<void> extendLease(Delivery delivery, Duration duration) =>
      _broker.extendLease(delivery, duration);

  @override
  Future<void> deadLetter(
    Delivery delivery, {
    String? reason,
    Map<String, Object?>? meta,
  }) => _broker.deadLetter(delivery, reason: reason, meta: meta);

  @override
  Future<int?> pendingCount(String queue) => _broker.pendingCount(queue);

  @override
  Future<void> publish(Envelope envelope) => _broker.publish(envelope);
}
