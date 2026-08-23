import 'package:stem/src/core/envelope.dart';

/// Tracks deliveries currently being executed by a worker.
///
/// Keeping active-delivery accounting outside the worker makes shutdown,
/// heartbeat, and observability code depend on one lifecycle component rather
/// than mutating several loosely-coupled maps. Worker-local handles are used
/// because some durable brokers reuse a row ID as the receipt after lease
/// expiry.
class WorkerDeliveryTracker {
  /// Active deliveries keyed by a worker-local tracking handle.
  final Map<int, WorkerActiveDelivery> _active = {};
  int _nextTrackingHandle = 0;
  final Map<String, int> _inflightPerQueue = {};
  int _inflight = 0;

  /// Active deliveries keyed by a worker-local tracking handle.
  Map<int, WorkerActiveDelivery> get active => _active;

  /// In-flight counts grouped by queue.
  Map<String, int> get inflightPerQueue => _inflightPerQueue;

  /// Total number of active deliveries.
  int get inflight => _inflight;

  /// Adds a delivery to the active set.
  WorkerActiveDelivery track(
    Delivery delivery, {
    required DateTime startedAt,
  }) {
    final envelope = delivery.envelope;
    final active = WorkerActiveDelivery(
      queue: envelope.queue,
      startedAt: startedAt,
      envelope: envelope,
      delivery: delivery,
    );
    _active[++_nextTrackingHandle] = active;
    _inflight += 1;
    _inflightPerQueue[envelope.queue] =
        (_inflightPerQueue[envelope.queue] ?? 0) + 1;
    return active;
  }

  /// Removes a delivery from the active set, if it is still tracked.
  WorkerActiveDelivery? release(Delivery delivery) {
    int? handle;
    for (final entry in _active.entries) {
      if (identical(entry.value.delivery, delivery)) {
        handle = entry.key;
        break;
      }
    }
    if (handle == null) return null;
    final active = _active.remove(handle);
    if (active == null) return null;

    _inflight = _inflight > 0 ? _inflight - 1 : 0;
    final queueCount = (_inflightPerQueue[active.queue] ?? 0) - 1;
    if (queueCount <= 0) {
      _inflightPerQueue.remove(active.queue);
    } else {
      _inflightPerQueue[active.queue] = queueCount;
    }
    return active;
  }

  /// Returns the active delivery for [envelopeId], if any.
  WorkerActiveDelivery? forEnvelopeId(String envelopeId) {
    for (final delivery in _active.values) {
      if (delivery.envelope.id == envelopeId) return delivery;
    }
    return null;
  }

  /// Returns the active record for the exact broker [delivery].
  WorkerActiveDelivery? forDelivery(Delivery delivery) {
    for (final active in _active.values) {
      if (identical(active.delivery, delivery)) return active;
    }
    return null;
  }

  /// Whether at least one delivery for [envelopeId] is active.
  bool containsEnvelopeId(String envelopeId) =>
      _active.values.any((delivery) => delivery.envelope.id == envelopeId);

  /// Clears all active-delivery accounting during worker shutdown.
  void clear() {
    _active.clear();
    _inflightPerQueue.clear();
    _inflight = 0;
  }
}

/// A delivery and its worker-local execution timestamps.
class WorkerActiveDelivery {
  /// Creates an active delivery record.
  WorkerActiveDelivery({
    required this.queue,
    required this.startedAt,
    required this.envelope,
    required this.delivery,
  });

  /// Queue containing the delivery.
  final String queue;

  /// Time at which execution began.
  final DateTime startedAt;

  /// Original task envelope.
  final Envelope envelope;

  /// Broker delivery wrapper.
  final Delivery delivery;

  /// Most recent successful lease renewal.
  DateTime? lastLeaseRenewal;
}
