import 'dart:async';

import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/envelope.dart';
import 'package:stem/src/core/stem_event.dart';
import 'package:stem/src/core/clock.dart';

const String _queueEventEnvelopeName = '__stem.queue.event__';
const String _queueEventChannelPrefix = 'stem:events';

String _queueEventChannel(String queue) => '$_queueEventChannelPrefix:$queue';

/// Represents a custom queue event emitted through [QueueEventsProducer].
class QueueCustomEvent implements StemEvent {
  /// Creates a queue custom event.
  const QueueCustomEvent({
    required this.id,
    required this.queue,
    required this.name,
    required this.payload,
    required this.emittedAt,
    this.headers = const {},
    this.meta = const {},
  });

  /// Message identifier used by the underlying broker envelope.
  final String id;

  /// Queue scope for this event.
  final String queue;

  /// Custom event name.
  final String name;

  /// Event payload.
  final Map<String, Object?> payload;

  /// Timestamp when the event was emitted.
  final DateTime emittedAt;

  /// Event headers.
  final Map<String, String> headers;

  /// Additional metadata supplied by the publisher.
  final Map<String, Object?> meta;

  @override
  String get eventName => name;

  @override
  DateTime get occurredAt => emittedAt;

  @override
  Map<String, Object?> get attributes => {
    'id': id,
    'queue': queue,
    'name': name,
    'payload': payload,
    'headers': headers,
    'meta': meta,
  };

  /// Converts the event to a JSON-compatible map.
  Map<String, Object?> toJson() => {
    'id': id,
    'queue': queue,
    'name': name,
    'payload': payload,
    'emittedAt': emittedAt.toIso8601String(),
    'headers': headers,
    'meta': meta,
  };
}

/// Emits queue-scoped custom events.
class QueueEventsProducer {
  /// Creates a queue event producer bound to a [broker].
  const QueueEventsProducer({required this.broker});

  /// Broker used for event delivery.
  final Broker broker;

  /// Emits [eventName] on [queue] and returns the event id.
  Future<String> emit(
    String queue,
    String eventName, {
    Map<String, Object?> payload = const {},
    Map<String, String> headers = const {},
    Map<String, Object?> meta = const {},
  }) async {
    final normalizedQueue = queue.trim();
    if (normalizedQueue.isEmpty) {
      throw ArgumentError.value(queue, 'queue', 'Queue name must not be empty');
    }
    final normalizedEventName = eventName.trim();
    if (normalizedEventName.isEmpty) {
      throw ArgumentError.value(
        eventName,
        'eventName',
        'Event name must not be empty',
      );
    }

    final emittedAt = stemNow().toUtc();
    final envelope = Envelope(
      name: _queueEventEnvelopeName,
      args: {
        'eventName': normalizedEventName,
        'payload': payload,
        'queue': normalizedQueue,
        'emittedAt': emittedAt.toIso8601String(),
      },
      headers: headers,
      queue: normalizedQueue,
      meta: meta,
    );
    await broker.publish(
      envelope,
      routing: RoutingInfo.broadcast(
        channel: _queueEventChannel(normalizedQueue),
      ),
    );
    return envelope.id;
  }
}

/// Listens for queue-scoped custom events emitted by [QueueEventsProducer].
class QueueEvents {
  /// Creates a queue event listener for [queue].
  QueueEvents({
    required this.broker,
    required String queue,
    String? consumerName,
    this.prefetch = 10,
  }) : queue = _normalizeQueue(queue),
       consumerName =
           consumerName ??
           'stem-queue-events-${generateEnvelopeId().replaceAll('-', '')}';

  /// Broker used for event consumption.
  final Broker broker;

  /// Queue scope for this listener.
  final String queue;

  /// Consumer identity used by broker adapters.
  final String consumerName;

  /// Prefetch size used by broker consumption.
  final int prefetch;

  StreamSubscription<Delivery>? _subscription;
  final StreamController<QueueCustomEvent> _events =
      StreamController<QueueCustomEvent>.broadcast();
  bool _started = false;
  bool _closed = false;

  /// Stream of received custom events.
  Stream<QueueCustomEvent> get events => _events.stream;

  /// Returns a filtered stream for [eventName].
  Stream<QueueCustomEvent> on(String eventName) {
    final normalized = eventName.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        eventName,
        'eventName',
        'Event name must not be empty',
      );
    }
    return events.where((event) => event.name == normalized);
  }

  /// Starts consuming queue events.
  Future<void> start() async {
    if (_closed) {
      throw StateError('QueueEvents is already closed.');
    }
    if (_started) {
      return;
    }
    _started = true;
    _subscription = broker
        .consume(
          RoutingSubscription(
            queues: const [],
            broadcastChannels: [
              _queueEventChannel(queue),
            ],
          ),
          prefetch: prefetch,
          consumerName: consumerName,
        )
        .listen(
          _onDelivery,
          onError: (Object error, StackTrace stackTrace) {
            _emitError(error, stackTrace);
          },
        );
  }

  /// Stops consuming events and closes the stream.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _subscription?.cancel();
    _subscription = null;
    await _events.close();
  }

  Future<void> _onDelivery(Delivery delivery) async {
    try {
      final event = _eventFromEnvelope(delivery.envelope);
      if (!_closed && event != null && event.queue == queue) {
        _events.add(event);
      }
    } on Object catch (error, stackTrace) {
      _emitError(error, stackTrace);
    } finally {
      try {
        await broker.ack(delivery);
      } on Object {
        // Best-effort acknowledgement to avoid poisoning the stream.
      }
    }
  }

  void _emitError(Object error, StackTrace stackTrace) {
    if (_closed || _events.isClosed) {
      return;
    }
    _events.addError(error, stackTrace);
  }
}

String _normalizeQueue(String queue) {
  final normalized = queue.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(queue, 'queue', 'Queue name must not be empty');
  }
  return normalized;
}

QueueCustomEvent? _eventFromEnvelope(Envelope envelope) {
  if (envelope.name != _queueEventEnvelopeName) {
    return null;
  }
  final args = envelope.args;
  final eventName = args['eventName']?.toString();
  if (eventName == null || eventName.trim().isEmpty) {
    throw const FormatException('Queue event is missing "eventName".');
  }
  final queue = (args['queue']?.toString() ?? envelope.queue).trim();
  if (queue.isEmpty) {
    throw const FormatException('Queue event is missing "queue".');
  }
  final emittedAtRaw = args['emittedAt']?.toString();
  final emittedAt = emittedAtRaw == null
      ? envelope.enqueuedAt.toUtc()
      : DateTime.parse(emittedAtRaw).toUtc();

  final rawPayload = args['payload'];
  final payload = rawPayload is Map<Object?, Object?>
      ? rawPayload.cast<String, Object?>()
      : const <String, Object?>{};

  return QueueCustomEvent(
    id: envelope.id,
    queue: queue,
    name: eventName.trim(),
    payload: payload,
    emittedAt: emittedAt,
    headers: envelope.headers,
    meta: envelope.meta,
  );
}
