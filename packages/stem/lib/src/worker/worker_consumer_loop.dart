import 'dart:async';

import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/envelope.dart';

/// Handles broker subscription ownership for a worker.
///
/// Task execution, control-command processing, and event reporting remain
/// owned by the worker. This class only manages subscription replacement,
/// cancellation, and the asynchronous error boundary around stream data
/// callbacks.
class WorkerConsumerLoop {
  /// Creates a consumer loop for [broker].
  WorkerConsumerLoop({required QueueBroker broker}) : _broker = broker;

  final QueueBroker _broker;
  final Map<String, StreamSubscription<Delivery>> _subscriptions = {};
  final Set<String> _queueSubscriptionNames = <String>{};

  /// Names of task-queue subscriptions currently owned by this loop.
  Iterable<String> get queueSubscriptionNames =>
      List.unmodifiable(_queueSubscriptionNames);

  /// Whether a subscription with [name] is already registered.
  bool contains(String name) => _subscriptions.containsKey(name);

  /// Replaces all task-queue subscriptions while leaving control subscriptions
  /// intact.
  Future<void> replaceQueueSubscriptions({
    required Iterable<String> queues,
    required Iterable<String> broadcastChannels,
    required int prefetch,
    required Future<void> Function(Delivery delivery) onDelivery,
    required void Function(Delivery delivery, Object error, StackTrace stack)
    onDeliveryError,
    required void Function(Object error, StackTrace stack) onStreamError,
    String? consumerName,
  }) async {
    await cancel(_queueSubscriptionNames);

    final resolvedQueues = queues.toList(growable: false);
    final resolvedBroadcasts = broadcastChannels.toList(growable: false);
    for (var index = 0; index < resolvedQueues.length; index += 1) {
      final queueName = resolvedQueues[index];
      subscribe(
        name: queueName,
        routing: RoutingSubscription(
          queues: [queueName],
          broadcastChannels: index == 0 ? resolvedBroadcasts : const <String>[],
        ),
        prefetch: prefetch,
        consumerName: consumerName,
        queueSubscription: true,
        onDelivery: onDelivery,
        onDeliveryError: onDeliveryError,
        onStreamError: onStreamError,
      );
    }
  }

  /// Adds one subscription, typically for a worker control queue.
  void subscribe({
    required String name,
    required RoutingSubscription routing,
    required Future<void> Function(Delivery delivery) onDelivery,
    required void Function(Delivery delivery, Object error, StackTrace stack)
    onDeliveryError,
    required void Function(Object error, StackTrace stack) onStreamError,
    int prefetch = 1,
    String? consumerName,
    bool queueSubscription = false,
  }) {
    if (_subscriptions.containsKey(name)) return;

    final stream = _broker.consume(
      routing,
      prefetch: prefetch,
      consumerName: consumerName,
    );
    // The loop owns all subscriptions and cancels them from [cancel] or
    // [close], so this is intentionally not left to a caller.
    // ignore: cancel_subscriptions
    final subscription = stream.listen(
      (delivery) {
        final task = onDelivery(delivery);
        unawaited(
          task.catchError((Object error, StackTrace stack) {
            onDeliveryError(delivery, error, stack);
          }),
        );
      },
      onError: onStreamError,
    );
    _subscriptions[name] = subscription;
    if (queueSubscription) {
      _queueSubscriptionNames.add(name);
    }
  }

  /// Cancels subscriptions named in [names].
  Future<void> cancel(Iterable<String> names) async {
    for (final name in List<String>.from(names)) {
      final subscription = _subscriptions.remove(name);
      _queueSubscriptionNames.remove(name);
      if (subscription == null) continue;
      try {
        await subscription.cancel();
      } on Object {
        // A broker may already have closed its stream during shutdown. The
        // worker owns the lifecycle, so cancellation remains best effort.
      }
    }
  }

  /// Cancels every subscription owned by this loop.
  Future<void> close() async {
    await cancel(_subscriptions.keys);
  }
}
