import 'dart:async';
import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/envelope.dart';

/// In-memory broker for testing and local development.
class InMemoryBroker implements Broker {
  /// Creates an in-memory broker with configurable timing defaults.
  InMemoryBroker({
    this.namespace = 'stem',
    this.delayedInterval = const Duration(milliseconds: 200),
    this.claimInterval = const Duration(seconds: 5),
    this.defaultVisibilityTimeout = const Duration(seconds: 30),
  }) {
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

  final Map<String, _QueueState> _queues = {};

  Timer? _delayedTimer;
  Timer? _claimTimer;
  bool _disposed = false;

  _QueueState _state(String queue) =>
      _queues.putIfAbsent(queue, () => _QueueState(queue));

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
  }

  @override
  Future<void> close() async {
    dispose();
  }

  @override
  Future<void> publish(Envelope envelope, {RoutingInfo? routing}) async {
    final resolvedRoute =
        routing ??
        RoutingInfo.queue(queue: envelope.queue, priority: envelope.priority);
    if (resolvedRoute.isBroadcast) {
      throw UnsupportedError(
        'InMemoryBroker does not support broadcast routing.',
      );
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

  Future<void> _drainDelayed(DateTime now) async {
    if (_disposed) return;
    for (final state in _queues.values) {
      state.moveDue(now);
    }
  }

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
    if (subscription.broadcastChannels.isNotEmpty) {
      throw UnsupportedError(
        'InMemoryBroker does not support broadcast subscriptions.',
      );
    }
    if (subscription.queues.isEmpty) {
      throw ArgumentError(
        'RoutingSubscription must specify at least one queue.',
      );
    }
    if (subscription.queues.length > 1) {
      throw UnsupportedError(
        'InMemoryBroker currently supports consuming a single queue at a time.',
      );
    }
    final queue = subscription.queues.first;
    final state = _state(queue);
    final consumer =
        consumerName ?? 'consumer-${DateTime.now().microsecondsSinceEpoch}';

    late StreamController<Delivery> controller;
    controller = StreamController<Delivery>.broadcast(
      onListen: () async {
        while (!controller.isClosed) {
          final delivery = await state.nextDelivery(
            consumer: consumer,
            prefetch: prefetch,
            defaultVisibilityTimeout: defaultVisibilityTimeout,
          );
          if (controller.isClosed) break;
          controller.add(delivery);
        }
      },
      onCancel: () {
        state.cancelWaiters(consumer);
        unawaited(controller.close());
      },
    );
    return controller.stream;
  }

  @override
  Future<void> ack(Delivery delivery) async {
    _state(delivery.envelope.queue).ack(delivery.receipt);
  }

  @override
  Future<void> nack(Delivery delivery, {bool requeue = true}) async {
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
    _state(
      delivery.envelope.queue,
    ).deadLetter(delivery.receipt, reason: reason, meta: meta);
  }

  @override
  Future<void> extendLease(Delivery delivery, Duration by) async {
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
  Future<void> purge(String queue) async {
    _state(queue).purge();
  }

  @override
  Future<int?> pendingCount(String queue) async => _state(queue).pending;

  @override
  Future<int?> inflightCount(String queue) async => _state(queue).inflight;
}

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
  final List<Completer<void>> _waiters = [];

  int _sequence = 0;

  void dispose() {
    for (final completer in _waiters) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
    _waiters.clear();
  }

  void cancelWaiters(String consumer) {
    _consumerInFlight.remove(consumer);
    for (final completer in _waiters) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
    _waiters.clear();
  }

  void enqueue(Envelope envelope) {
    _ready.add(envelope);
    _notify();
  }

  void addDelayed(Envelope envelope) {
    _delayed.add(
      _DelayedEntry(envelope: envelope, availableAt: envelope.notBefore!),
    );
  }

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

  Future<Delivery> nextDelivery({
    required String consumer,
    required int prefetch,
    required Duration defaultVisibilityTimeout,
  }) async {
    while (true) {
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

  void extendLease(String receipt, Duration by) {
    final entry = _pending[receipt];
    if (entry == null) return;
    entry.leaseExpiresAt = DateTime.now().add(by);
  }

  void purge() {
    _ready.clear();
    _delayed.clear();
    _pending.clear();
    deadLetters.clear();
    _consumerInFlight.clear();
    _notify();
  }

  String _nextReceipt() => '$name:${_sequence++}';

  int get pending => _ready.length + _delayed.length;

  int get inflight => _pending.length;

  void _notify() {
    if (_waiters.isEmpty) return;
    for (final completer in _waiters) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
    _waiters.clear();
  }
}

class _DelayedEntry {
  _DelayedEntry({required this.envelope, required this.availableAt});

  final Envelope envelope;
  final DateTime availableAt;
}

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
