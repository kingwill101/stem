import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/envelope.dart';
import 'package:uuid/uuid.dart';

/// In-memory broker for testing and local development.
class InMemoryBroker implements Broker {
  /// Creates an in-memory broker with configurable timing defaults.
  InMemoryBroker({
    this.namespace = 'stem',
    this.delayedInterval = const Duration(milliseconds: 200),
    this.claimInterval = const Duration(seconds: 5),
    this.defaultVisibilityTimeout = const Duration(seconds: 30),
  }) {
    _namespaceRefs[namespace] = (_namespaceRefs[namespace] ?? 0) + 1;
    _delayedTimer = Timer.periodic(
      delayedInterval,
      (_) => _drainDelayed(DateTime.now()),
    );
    _claimTimer = Timer.periodic(
      claimInterval,
      (_) => _reclaimExpired(DateTime.now()),
    );
  }

  /// Namespace prefix applied to generated queue names.
  final String namespace;

  /// Interval used to drain delayed messages.
  final Duration delayedInterval;

  /// Interval used to reclaim expired leases.
  final Duration claimInterval;

  /// Default visibility timeout for claimed deliveries.
  final Duration defaultVisibilityTimeout;

  static final Map<String, _BroadcastHub> _broadcastHubs = {};
  static final Map<String, int> _namespaceRefs = {};

  final Map<String, _QueueState> _queues = {};
  final Set<_BroadcastSubscription> _activeBroadcastSubscriptions = {};

  Timer? _delayedTimer;
  Timer? _claimTimer;
  bool _disposed = false;

  _QueueState _state(String queue) =>
      _queues.putIfAbsent(queue, () => _QueueState(queue));

  _BroadcastHub get _broadcastHub =>
      _broadcastHubs.putIfAbsent(namespace, () => _BroadcastHub(namespace));

  @override
  bool get supportsDelayed => true;

  @override
  bool get supportsPriority => false;

  /// Releases timers and in-memory queue state.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _delayedTimer?.cancel();
    _claimTimer?.cancel();
    for (final q in _queues.values) {
      q.dispose();
    }
    for (final subscription in _activeBroadcastSubscriptions.toList()) {
      subscription.close();
    }
    _activeBroadcastSubscriptions.clear();
    final remaining = (_namespaceRefs[namespace] ?? 1) - 1;
    if (remaining <= 0) {
      _namespaceRefs.remove(namespace);
      _broadcastHubs.remove(namespace);
    } else {
      _namespaceRefs[namespace] = remaining;
    }
  }

  @override
  /// Closes the broker and releases in-memory resources.
  Future<void> close() async {
    dispose();
  }

  @override
  /// Enqueues a message into the in-memory queue or delay set.
  Future<void> publish(Envelope envelope, {RoutingInfo? routing}) async {
    final resolvedRoute =
        routing ??
        RoutingInfo.queue(queue: envelope.queue, priority: envelope.priority);
    if (resolvedRoute.isBroadcast) {
      final channel = resolvedRoute.broadcastChannel ?? envelope.queue;
      final message = envelope.copyWith(queue: channel);
      _broadcastHub.publish(
        channel: channel,
        envelope: message,
        delivery: resolvedRoute.delivery ?? 'at-least-once',
      );
      return;
    }
    final targetQueue = resolvedRoute.queue ?? envelope.queue;
    final state = _state(targetQueue);
    final msg = envelope.copyWith(
      queue: targetQueue,
      priority: resolvedRoute.priority ?? envelope.priority,
    );

    if (msg.notBefore != null && msg.notBefore!.isAfter(DateTime.now())) {
      state.addDelayed(msg);
    } else {
      state.enqueue(msg);
    }
  }

  /// Moves delayed messages that are due into the ready queue.
  Future<void> _drainDelayed(DateTime now) async {
    if (_disposed) return;
    for (final state in _queues.values) {
      state.moveDue(now);
    }
  }

  /// Reclaims expired in-flight deliveries back into the ready queue.
  Future<void> _reclaimExpired(DateTime now) async {
    if (_disposed) return;
    for (final state in _queues.values) {
      state.reclaimExpired(now);
    }
  }

  @override
  Stream<Delivery> consume(
    RoutingSubscription subscription, {
    int prefetch = 1,
    String? consumerGroup,
    String? consumerName,
  }) {
    if (subscription.queues.length > 1) {
      throw UnsupportedError(
        'InMemoryBroker currently supports consuming a single queue at a time.',
      );
    }
    final queue = subscription.queues.firstOrNull;
    final state = queue == null ? null : _state(queue);
    final consumer = consumerName ?? const Uuid().v7();
    final consumerKey = '${consumerGroup ?? 'default'}::$consumer';
    _BroadcastSubscription? broadcastSubscription;
    var active = true;

    late StreamController<Delivery> controller;
    controller = StreamController<Delivery>(
      onListen: () async {
        if (subscription.broadcastChannels.isNotEmpty) {
          broadcastSubscription = _broadcastHub.subscribe(
            consumer: consumerKey,
            channels: subscription.broadcastChannels,
            onDelivery: (delivery) {
              if (controller.isClosed) return;
              controller.add(delivery);
            },
          );
          _activeBroadcastSubscriptions.add(broadcastSubscription!);
        }

        if (state == null) {
          return;
        }

        state.resumeConsumer(consumer);
        try {
          while (active && !controller.isClosed) {
            final delivery = await state.nextDelivery(
              consumer: consumer,
              prefetch: prefetch,
              defaultVisibilityTimeout: defaultVisibilityTimeout,
            );
            if (!active || controller.isClosed || !controller.hasListener) {
              state.requeue(delivery.receipt);
              break;
            }
            controller.add(delivery);
          }
        } on _ConsumerCancelled {
          return;
        }
      },
      onCancel: () {
        active = false;
        state?.cancelWaiters(consumer);
        final subscription = broadcastSubscription;
        if (subscription != null) {
          subscription.close();
          _activeBroadcastSubscriptions.remove(subscription);
        }
      },
    );
    return controller.stream;
  }

  @override
  /// Acknowledges a delivery, removing it from in-flight tracking.
  Future<void> ack(Delivery delivery) async {
    if (delivery.route.isBroadcast) {
      _broadcastHub.ack(delivery.receipt);
      return;
    }
    _state(delivery.envelope.queue).ack(delivery.receipt);
  }

  @override
  /// Rejects a delivery, optionally requeuing it.
  ///
  /// Broadcast deliveries are fire-and-forget in this broker. For broadcast
  /// routes, `nack` records an ack in the broadcast hub and ignores `requeue`.
  Future<void> nack(Delivery delivery, {bool requeue = true}) async {
    if (delivery.route.isBroadcast) {
      _broadcastHub.ack(delivery.receipt);
      return;
    }
    final state = _state(delivery.envelope.queue);
    final envelope = state.ack(delivery.receipt);
    if (envelope != null && requeue) {
      state.enqueue(envelope);
    }
  }

  @override
  Future<void> deadLetter(
    Delivery delivery, {
    String? reason,
    Map<String, Object?>? meta,
  }) async {
    if (delivery.route.isBroadcast) {
      _broadcastHub.ack(delivery.receipt);
      return;
    }
    _state(
      delivery.envelope.queue,
    ).deadLetter(delivery.receipt, reason: reason, meta: meta);
  }

  @override
  /// Extends the visibility lease for an in-flight delivery.
  Future<void> extendLease(Delivery delivery, Duration by) async {
    if (delivery.route.isBroadcast) {
      return;
    }
    _state(delivery.envelope.queue).extendLease(delivery.receipt, by);
  }

  @override
  Future<DeadLetterPage> listDeadLetters(
    String queue, {
    int limit = 50,
    int offset = 0,
  }) async {
    final state = _state(queue);
    final entries = List<DeadLetterEntry>.from(state.deadLetters)
      ..sort((a, b) => b.deadAt.compareTo(a.deadAt));
    if (entries.isEmpty || limit <= 0) {
      return const DeadLetterPage(entries: []);
    }
    final total = entries.length;
    final start = offset < 0 ? 0 : offset;
    if (start >= total) {
      return const DeadLetterPage(entries: []);
    }
    var end = start + limit;
    if (end > total) {
      end = total;
    }
    final slice = entries.sublist(start, end);
    final nextOffset = end < total ? end : null;
    return DeadLetterPage(entries: slice, nextOffset: nextOffset);
  }

  @override
  /// Fetches a single dead-letter entry by id.
  Future<DeadLetterEntry?> getDeadLetter(String queue, String id) async {
    final state = _state(queue);
    return state.deadLetters.firstWhereOrNull(
      (entry) => entry.envelope.id == id,
    );
  }

  @override
  Future<DeadLetterReplayResult> replayDeadLetters(
    String queue, {
    int limit = 50,
    DateTime? since,
    Duration? delay,
    bool dryRun = false,
  }) async {
    if (limit <= 0) {
      return DeadLetterReplayResult(entries: const [], dryRun: dryRun);
    }
    final state = _state(queue);
    final candidates = state.deadLetters.where((entry) {
      if (since == null) return true;
      return !entry.deadAt.isBefore(since);
    }).toList()..sort((a, b) => a.deadAt.compareTo(b.deadAt));
    final selected = candidates.take(limit).toList();
    if (dryRun || selected.isEmpty) {
      return DeadLetterReplayResult(entries: selected, dryRun: true);
    }
    final now = DateTime.now();
    for (final entry in selected) {
      state.deadLetters.remove(entry);
      final replayEnvelope = entry.envelope.copyWith(
        attempt: entry.envelope.attempt + 1,
        notBefore: delay != null ? now.add(delay) : null,
      );
      await publish(replayEnvelope.copyWith(queue: queue));
    }
    return DeadLetterReplayResult(entries: selected, dryRun: false);
  }

  @override
  Future<int> purgeDeadLetters(
    String queue, {
    DateTime? since,
    int? limit,
  }) async {
    final state = _state(queue);
    final candidates = state.deadLetters.where((entry) {
      if (since == null) return true;
      return !entry.deadAt.isBefore(since);
    }).toList()..sort((a, b) => b.deadAt.compareTo(a.deadAt));
    final toRemove =
        limit != null && limit >= 0
              ? candidates.take(limit).toList()
              : candidates
          ..forEach(state.deadLetters.remove);
    return toRemove.length;
  }

  @override
  /// Purges all messages from a queue.
  Future<void> purge(String queue) async {
    _state(queue).purge();
  }

  @override
  Future<int?> pendingCount(String queue) async => _state(queue).pending;

  @override
  Future<int?> inflightCount(String queue) async => _state(queue).inflight;
}

/// Internal queue state for in-memory broker operations.
class _QueueState {
  _QueueState(this.name);

  final String name;

  final ListQueue<Envelope> _ready = ListQueue();
  final PriorityQueue<_DelayedEntry> _delayed = HeapPriorityQueue(
    (a, b) => a.availableAt.compareTo(b.availableAt),
  );
  final Map<String, _PendingEntry> _pending = {};
  final List<DeadLetterEntry> deadLetters = [];
  final Map<String, int> _consumerInFlight = {};
  final Set<String> _cancelledConsumers = {};
  final List<Completer<void>> _waiters = [];

  int _sequence = 0;

  /// Completes outstanding waiters when the broker is shutting down.
  void dispose() {
    for (final completer in _waiters) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
    _waiters.clear();
  }

  /// Cancels pending waiters for a consumer and clears in-flight tracking.
  void cancelWaiters(String consumer) {
    _cancelledConsumers.add(consumer);
    _consumerInFlight.remove(consumer);
    for (final completer in _waiters) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
    _waiters.clear();
  }

  /// Clears cancellation state when a consumer re-subscribes.
  void resumeConsumer(String consumer) {
    _cancelledConsumers.remove(consumer);
  }

  /// Enqueues a ready-to-run envelope and wakes consumers.
  void enqueue(Envelope envelope) {
    _ready.add(envelope);
    _notify();
  }

  /// Stores a delayed envelope until its scheduled time.
  void addDelayed(Envelope envelope) {
    _delayed.add(
      _DelayedEntry(envelope: envelope, availableAt: envelope.notBefore!),
    );
  }

  /// Moves any due delayed entries into the ready queue.
  void moveDue(DateTime now) {
    var moved = false;
    while (_delayed.isNotEmpty) {
      final entry = _delayed.first;
      if (entry.availableAt.isAfter(now)) {
        break;
      }
      _delayed.removeFirst();
      _ready.add(entry.envelope.copyWith());
      moved = true;
    }
    if (moved) {
      _notify();
    }
  }

  /// Returns the next delivery for a consumer, waiting if none available.
  Future<Delivery> nextDelivery({
    required String consumer,
    required int prefetch,
    required Duration defaultVisibilityTimeout,
  }) async {
    while (true) {
      if (_cancelledConsumers.contains(consumer)) {
        throw _ConsumerCancelled(consumer);
      }
      moveDue(DateTime.now());

      final inFlight = _consumerInFlight[consumer] ?? 0;
      if (inFlight < prefetch && _ready.isNotEmpty) {
        final envelope = _ready.removeFirst();
        final receipt = _nextReceipt();
        final visibility =
            envelope.visibilityTimeout ?? defaultVisibilityTimeout;
        final expiresAt = visibility == Duration.zero
            ? null
            : DateTime.now().add(visibility);
        final delivery = Delivery(
          envelope: envelope,
          receipt: receipt,
          leaseExpiresAt: expiresAt,
          route: RoutingInfo.queue(
            queue: envelope.queue,
            priority: envelope.priority,
          ),
        );
        _pending[receipt] = _PendingEntry(
          delivery: delivery,
          consumer: consumer,
          leaseExpiresAt: expiresAt,
        );
        _consumerInFlight[consumer] = inFlight + 1;
        return delivery;
      }

      final completer = Completer<void>();
      _waiters.add(completer);
      await completer.future;
    }
  }

  /// Acknowledges a delivery and frees a consumer slot.
  Envelope? ack(String receipt) {
    final entry = _pending.remove(receipt);
    if (entry == null) {
      return null;
    }
    final consumer = entry.consumer;
    final count = _consumerInFlight[consumer] ?? 0;
    if (count > 0) {
      _consumerInFlight[consumer] = count - 1;
    }
    _notify();
    return entry.delivery.envelope;
  }

  /// Moves a delivery to the dead-letter list with optional metadata.
  void deadLetter(
    String receipt, {
    String? reason,
    Map<String, Object?>? meta,
  }) {
    final envelope = ack(receipt);
    if (envelope == null) {
      return;
    }
    deadLetters.add(
      DeadLetterEntry(
        envelope: envelope,
        reason: reason,
        meta: meta ?? const {},
        deadAt: DateTime.now(),
      ),
    );
  }

  /// Re-queues expired leases back to the ready queue.
  void reclaimExpired(DateTime now) {
    final expired = _pending.entries
        .where(
          (entry) =>
              entry.value.leaseExpiresAt != null &&
              !entry.value.leaseExpiresAt!.isAfter(now),
        )
        .map((entry) => entry.key)
        .toList();

    for (final receipt in expired) {
      final entry = _pending.remove(receipt);
      if (entry == null) continue;
      final consumer = entry.consumer;
      final count = _consumerInFlight[consumer] ?? 0;
      if (count > 0) {
        _consumerInFlight[consumer] = count - 1;
      }
      _ready.add(entry.delivery.envelope);
    }

    if (expired.isNotEmpty) {
      _notify();
    }
  }

  /// Extends the lease for an in-flight delivery.
  void extendLease(String receipt, Duration by) {
    final entry = _pending[receipt];
    if (entry == null) return;
    entry.leaseExpiresAt = DateTime.now().add(by);
  }

  /// Clears all queues, in-flight deliveries, and dead letters.
  void purge() {
    _ready.clear();
    _delayed.clear();
    _pending.clear();
    deadLetters.clear();
    _consumerInFlight.clear();
    _notify();
  }

  /// Generates a monotonically increasing receipt identifier.
  String _nextReceipt() => '$name:${_sequence++}';

  /// Count of ready items waiting for delivery.
  int get pending => _ready.length;

  /// Count of deliveries currently leased to consumers.
  int get inflight => _pending.length;

  /// Wakes consumers waiting on the next delivery.
  void _notify() {
    if (_waiters.isEmpty) return;
    for (final completer in _waiters) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
    _waiters.clear();
  }

  /// Requeues an in-flight delivery back onto the ready queue.
  void requeue(String receipt) {
    final entry = _pending.remove(receipt);
    if (entry == null) {
      return;
    }
    final consumer = entry.consumer;
    final count = _consumerInFlight[consumer] ?? 0;
    if (count > 0) {
      _consumerInFlight[consumer] = count - 1;
    }
    _ready.addFirst(entry.delivery.envelope);
    _notify();
  }
}

/// Delayed queue entry sorted by availability time.
class _DelayedEntry {
  _DelayedEntry({required this.envelope, required this.availableAt});

  final Envelope envelope;
  final DateTime availableAt;
}

/// Tracks an in-flight delivery and its lease metadata.
class _PendingEntry {
  _PendingEntry({
    required this.delivery,
    required this.consumer,
    this.leaseExpiresAt,
  });

  final Delivery delivery;
  final String consumer;
  DateTime? leaseExpiresAt;
}

class _ConsumerCancelled implements Exception {
  _ConsumerCancelled(this.consumer);

  final String consumer;
}

class _BroadcastHub {
  _BroadcastHub(this.namespace);

  final String namespace;
  static const int _maxHistory = 10000;
  final Map<String, Map<String, _BroadcastListener>> _listenersByChannel = {};
  final ListQueue<String> _messageOrder = ListQueue();
  final Map<String, _BroadcastMessage> _messagesByKey = {};
  final Map<String, Set<String>> _ackedByConsumer = {};

  _BroadcastSubscription subscribe({
    required String consumer,
    required List<String> channels,
    required void Function(Delivery delivery) onDelivery,
  }) {
    final listener = _BroadcastListener(
      id: const Uuid().v7(),
      consumer: consumer,
      onDelivery: onDelivery,
    );
    final uniqueChannels = channels.toSet();
    for (final channel in uniqueChannels) {
      final listeners = _listenersByChannel.putIfAbsent(channel, () => {});
      listeners[listener.id] = listener;
    }
    _deliverBacklog(listener: listener, channels: uniqueChannels);
    return _BroadcastSubscription(() {
      for (final channel in uniqueChannels) {
        final listeners = _listenersByChannel[channel];
        listeners?.remove(listener.id);
        if (listeners == null || listeners.isNotEmpty) {
          continue;
        }
        _listenersByChannel.remove(channel);
      }
    });
  }

  void publish({
    required String channel,
    required Envelope envelope,
    required String delivery,
  }) {
    final message = _BroadcastMessage(
      key: const Uuid().v7(),
      channel: channel,
      envelope: envelope.copyWith(),
      delivery: delivery,
    );
    _messagesByKey[message.key] = message;
    _messageOrder.addLast(message.key);
    _trimHistory();

    final listeners = _listenersByChannel[channel];
    if (listeners == null || listeners.isEmpty) {
      return;
    }
    final snapshot = listeners.values.toList(growable: false);
    for (final listener in snapshot) {
      if (_isAcked(listener.consumer, message.key)) continue;
      listener.onDelivery(_toDelivery(message, listener.consumer));
    }
  }

  void ack(String receipt) {
    try {
      final payload = jsonDecode(receipt);
      if (payload is! Map<String, dynamic>) {
        return;
      }
      final messageKey = payload['messageKey'] as String?;
      final consumer = payload['consumer'] as String?;
      if (messageKey == null || consumer == null) {
        return;
      }
      _ackedByConsumer.putIfAbsent(consumer, () => <String>{}).add(messageKey);
    } on Object {
      return;
    }
  }

  void _deliverBacklog({
    required _BroadcastListener listener,
    required Set<String> channels,
  }) {
    for (final messageKey in _messageOrder) {
      final message = _messagesByKey[messageKey];
      if (message == null) continue;
      if (!channels.contains(message.channel)) continue;
      if (_isAcked(listener.consumer, message.key)) continue;
      listener.onDelivery(_toDelivery(message, listener.consumer));
    }
  }

  Delivery _toDelivery(_BroadcastMessage message, String consumer) {
    return Delivery(
      envelope: message.envelope.copyWith(),
      receipt: jsonEncode({
        'messageKey': message.key,
        'consumer': consumer,
      }),
      leaseExpiresAt: null,
      route: RoutingInfo.broadcast(
        channel: message.channel,
        delivery: message.delivery,
      ),
    );
  }

  bool _isAcked(String consumer, String messageId) {
    final acked = _ackedByConsumer[consumer];
    if (acked == null) return false;
    return acked.contains(messageId);
  }

  void _trimHistory() {
    while (_messageOrder.length > _maxHistory) {
      final oldest = _messageOrder.removeFirst();
      _messagesByKey.remove(oldest);
      for (final acked in _ackedByConsumer.values) {
        acked.remove(oldest);
      }
    }
  }
}

class _BroadcastListener {
  _BroadcastListener({
    required this.id,
    required this.consumer,
    required this.onDelivery,
  });

  final String id;
  final String consumer;
  final void Function(Delivery delivery) onDelivery;
}

class _BroadcastSubscription {
  _BroadcastSubscription(this._onClose);

  final void Function() _onClose;
  bool _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    _onClose();
  }
}

class _BroadcastMessage {
  _BroadcastMessage({
    required this.key,
    required this.channel,
    required this.envelope,
    required this.delivery,
  });

  final String key;
  final String channel;
  final Envelope envelope;
  final String delivery;
}
