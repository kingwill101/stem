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
  WorkerConsumerLoop({required QueueBroker broker, this.onCancelError})
    : _broker = broker;

  final QueueBroker _broker;

  /// Reports cancellation failures while continuing to cancel other streams.
  final void Function(Object error, StackTrace stack)? onCancelError;
  final Map<String, StreamSubscription<Delivery>> _subscriptions = {};
  final Set<String> _queueSubscriptionNames = <String>{};
  int _pending = 0;
  Completer<void>? _drained;

  /// Waits for complete callbacks, including pre-execution work and postrun
  /// hooks. Call after cancelling subscriptions to establish quiescence.
  Future<void> drain() async {
    if (_pending == 0) return;
    await (_drained ??= Completer<void>()).future;
  }

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
    bool Function()? canSubscribe,
  }) async {
    await cancel(_queueSubscriptionNames);

    final resolvedQueues = queues.toList(growable: false);
    final resolvedBroadcasts = broadcastChannels.toList(growable: false);
    for (var index = 0; index < resolvedQueues.length; index += 1) {
      if (!(canSubscribe?.call() ?? true)) break;
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
        _pending += 1;
        final task = Future<void>.sync(() => onDelivery(delivery));
        unawaited(
          task
              .catchError((Object error, StackTrace stack) {
                onDeliveryError(delivery, error, stack);
              })
              .whenComplete(() {
                _pending -= 1;
                if (_pending == 0) {
                  _drained?.complete();
                  _drained = null;
                }
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
      } on Object catch (error, stack) {
        // A broker may already have closed its stream during shutdown. The
        // worker owns the lifecycle, so cancellation remains best effort.
        onCancelError?.call(error, stack);
      }
    }
  }

  /// Cancels every subscription owned by this loop.
  Future<void> close() async {
    await cancel(_subscriptions.keys);
  }
}
