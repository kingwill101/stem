/// Task envelopes and routing metadata.
///
/// This library defines the [Envelope], which is the serialized representation
/// of a task as it travels from a producer to a consumer. It also contains
/// [RoutingInfo] for describing how messages should be dispatched by brokers.
///
/// ## Envelopes
///
/// An [Envelope] contains:
/// - **Identity**: Unique ID and fully qualified task name.
/// - **Payload**: Arguments (`args`) and metadata (`headers`).
/// - **Scheduling**: `enqueuedAt`, `notBefore`, and `priority`.
/// - **Lifecycle**: `attempt` count and `maxRetries` limit.
/// - **Routing**: Target `queue` and visibility settings.
///
/// ## Routing
///
/// [RoutingInfo] provides flexible dispatching options:
/// - **Queue**: Point-to-point delivery with priority and exchange support.
/// - **Broadcast**: Fan-out delivery to all active listeners on a channel.
///
/// ## IDs and Receipts
///
/// - [Envelope.id]: The logical ID that follows the task across retries.
/// - [Delivery.receipt]: A broker-specific transient ID used for
///   acknowledgment (ACK) or lease extensions.
///
/// See also:
/// - `Broker` for the interface that consumes and publishes these types.
/// - `Stem` for the facade that creates envelopes.
library;

import 'dart:convert';

import 'package:uuid/uuid.dart';

/// Target classification for routing operations.
enum RoutingTargetType {
  /// Route to a named queue.
  queue,

  /// Route to a broadcast channel.
  broadcast,
}

/// Routing metadata that accompanies published envelopes.
///
/// Queue routes include optional exchange/routing-key context plus a priority
/// override. Broadcast routes reference a logical channel; brokers may map
/// that to underlying transport semantics.
class RoutingInfo {
  RoutingInfo._({
    required this.type,
    this.queue,
    this.exchange,
    this.routingKey,
    this.priority,
    this.broadcastChannel,
    this.delivery,
    Map<String, Object?>? meta,
  }) : meta = Map.unmodifiable(meta ?? const {});

  /// Creates a queue-based routing descriptor.
  factory RoutingInfo.queue({
    required String queue,
    String? exchange,
    String? routingKey,
    int? priority,
    Map<String, Object?>? meta,
  }) {
    final trimmed = queue.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(queue, 'queue', 'Queue must not be empty');
    }
    return RoutingInfo._(
      type: RoutingTargetType.queue,
      queue: trimmed,
      exchange: exchange,
      routingKey: routingKey,
      priority: priority,
      meta: meta,
    );
  }

  /// Creates a broadcast routing descriptor.
  factory RoutingInfo.broadcast({
    required String channel,
    String delivery = 'at-least-once',
    Map<String, Object?>? meta,
  }) {
    final trimmed = channel.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
        channel,
        'channel',
        'Broadcast channel must not be empty',
      );
    }
    return RoutingInfo._(
      type: RoutingTargetType.broadcast,
      broadcastChannel: trimmed,
      delivery: delivery,
      meta: meta,
    );
  }

  /// Parses routing metadata from JSON.
  factory RoutingInfo.fromJson(Map<String, Object?> json) {
    final type = json['type']?.toString();
    if (type == RoutingTargetType.broadcast.name) {
      final channel =
          json['broadcastChannel']?.toString() ??
          json['channel']?.toString() ??
          '';
      return RoutingInfo.broadcast(
        channel: channel,
        delivery: json['delivery']?.toString() ?? 'at-least-once',
        meta: (json['meta'] as Map?)?.cast<String, Object?>(),
      );
    }
    final queue = json['queue']?.toString() ?? '';
    return RoutingInfo.queue(
      queue: queue,
      exchange: json['exchange']?.toString(),
      routingKey: json['routingKey']?.toString(),
      priority: (json['priority'] as num?)?.toInt(),
      meta: (json['meta'] as Map?)?.cast<String, Object?>(),
    );
  }

  /// The routing target type (queue or broadcast).
  final RoutingTargetType type;

  /// Queue name for queue routing.
  final String? queue;

  /// Optional exchange name for queue routing.
  final String? exchange;

  /// Optional routing key used by the broker.
  final String? routingKey;

  /// Optional priority override for the published envelope.
  final int? priority;

  /// Broadcast channel identifier.
  final String? broadcastChannel;

  /// Delivery policy hint for broadcast routing.
  final String? delivery;

  /// Additional routing metadata.
  final Map<String, Object?> meta;

  /// Whether this routing info targets a broadcast channel.
  bool get isBroadcast => type == RoutingTargetType.broadcast;

  /// Serializes this routing descriptor to JSON.
  Map<String, Object?> toJson() => {
    'type': type.name,
    'queue': queue,
    'exchange': exchange,
    'routingKey': routingKey,
    'priority': priority,
    'broadcastChannel': broadcastChannel,
    'delivery': delivery,
    'meta': meta,
  };
}

/// Unique identifier generator used for task envelopes by default.
String generateEnvelopeId() => const Uuid().v7();

/// Task payload persisted inside a broker.
/// Since: 0.1.0
class Envelope {
  /// Creates an envelope for a task invocation.
  Envelope({
    required this.name,
    required this.args,
    String? id,
    Map<String, String>? headers,
    DateTime? enqueuedAt,
    this.notBefore,
    this.priority = 0,
    this.attempt = 0,
    this.maxRetries = 0,
    this.visibilityTimeout,
    this.queue = 'default',
    Map<String, Object?>? meta,
  }) : id = id ?? generateEnvelopeId(),
       headers = Map.unmodifiable(headers ?? const {}),
       enqueuedAt = enqueuedAt ?? DateTime.now(),
       meta = Map.unmodifiable(meta ?? const {});

  /// Builds an envelope from persisted JSON.
  factory Envelope.fromJson(Map<String, Object?> json) {
    return Envelope(
      id: json['id'] as String?,
      name: json['name']! as String,
      args: (json['args']! as Map).cast<String, Object?>(),
      headers: (json['headers'] as Map?)?.cast<String, String>(),
      enqueuedAt: json['enqueuedAt'] != null
          ? DateTime.parse(json['enqueuedAt']! as String)
          : null,
      notBefore: json['notBefore'] != null
          ? DateTime.parse(json['notBefore']! as String)
          : null,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      attempt: (json['attempt'] as num?)?.toInt() ?? 0,
      maxRetries: (json['maxRetries'] as num?)?.toInt() ?? 0,
      visibilityTimeout: json['visibilityTimeout'] != null
          ? Duration(milliseconds: (json['visibilityTimeout']! as num).toInt())
          : null,
      queue: json['queue'] as String? ?? 'default',
      meta: (json['meta'] as Map?)?.cast<String, Object?>(),
    );
  }

  /// Unique identifier for the logical task.
  final String id;

  /// Fully qualified task name.
  final String name;

  /// Arguments passed to the task handler.
  final Map<String, Object?> args;

  /// Arbitrary metadata headers (trace id, tenant, etc).
  final Map<String, String> headers;

  /// Time the envelope was enqueued.
  final DateTime enqueuedAt;

  /// Optional earliest execution timestamp.
  final DateTime? notBefore;

  /// Priority hint (adapter specific).
  final int priority;

  /// Current delivery attempt.
  final int attempt;

  /// Maximum allowed retries.
  final int maxRetries;

  /// Lease duration hint for brokers supporting visibility timeouts.
  final Duration? visibilityTimeout;

  /// Logical queue routing key.
  final String queue;

  /// Additional metadata persisted with the message.
  final Map<String, Object?> meta;

  /// Returns a copy of this envelope with updated fields.
  Envelope copyWith({
    String? id,
    Map<String, Object?>? args,
    Map<String, String>? headers,
    DateTime? enqueuedAt,
    DateTime? notBefore,
    int? priority,
    int? attempt,
    int? maxRetries,
    Duration? visibilityTimeout,
    String? queue,
    Map<String, Object?>? meta,
  }) {
    return Envelope(
      id: id ?? this.id,
      name: name,
      args: args ?? this.args,
      headers: headers ?? this.headers,
      enqueuedAt: enqueuedAt ?? this.enqueuedAt,
      notBefore: notBefore ?? this.notBefore,
      priority: priority ?? this.priority,
      attempt: attempt ?? this.attempt,
      maxRetries: maxRetries ?? this.maxRetries,
      visibilityTimeout: visibilityTimeout ?? this.visibilityTimeout,
      queue: queue ?? this.queue,
      meta: meta ?? this.meta,
    );
  }

  /// Serializes this envelope to JSON.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'args': args,
    'headers': headers,
    'enqueuedAt': enqueuedAt.toIso8601String(),
    'notBefore': notBefore?.toIso8601String(),
    'priority': priority,
    'attempt': attempt,
    'maxRetries': maxRetries,
    'visibilityTimeout': visibilityTimeout?.inMilliseconds,
    'queue': queue,
    'meta': meta,
  };

  /// Returns the JSON representation of the envelope.
  @override
  String toString() => jsonEncode(toJson());
}

/// Runtime wrapper containing the envelope plus broker-specific receipt info.
class Delivery {
  /// Creates a delivery wrapper for a broker receipt.
  Delivery({
    required this.envelope,
    required this.receipt,
    required this.leaseExpiresAt,
    RoutingInfo? route,
  }) : route =
           route ??
           RoutingInfo.queue(
             queue: envelope.queue,
             priority: envelope.priority,
           );

  /// The underlying envelope that was delivered.
  final Envelope envelope;

  /// Broker specific handle used for ack/nack/extend operations.
  final String receipt;

  /// When the current lease expires (if supported).
  final DateTime? leaseExpiresAt;

  /// Routing metadata resolved for this delivery.
  final RoutingInfo route;
}
