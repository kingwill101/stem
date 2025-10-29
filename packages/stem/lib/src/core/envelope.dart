import 'dart:convert';
import 'dart:math';

/// Target classification for routing operations.
enum RoutingTargetType { queue, broadcast }

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

  final RoutingTargetType type;
  final String? queue;
  final String? exchange;
  final String? routingKey;
  final int? priority;
  final String? broadcastChannel;
  final String? delivery;
  final Map<String, Object?> meta;

  bool get isBroadcast => type == RoutingTargetType.broadcast;
}

/// Unique identifier generator used for task envelopes by default.
String generateEnvelopeId() {
  final micros = DateTime.now().microsecondsSinceEpoch;
  final random = Random().nextInt(1 << 32);
  return '$micros-$random';
}

/// Task payload persisted inside a broker.
/// Since: 0.1.0
class Envelope {
  Envelope({
    String? id,
    required this.name,
    required this.args,
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

  static Envelope fromJson(Map<String, Object?> json) {
    return Envelope(
      id: json['id'] as String?,
      name: json['name'] as String,
      args: (json['args'] as Map).cast<String, Object?>(),
      headers: (json['headers'] as Map?)?.cast<String, String>(),
      enqueuedAt: json['enqueuedAt'] != null
          ? DateTime.parse(json['enqueuedAt'] as String)
          : null,
      notBefore: json['notBefore'] != null
          ? DateTime.parse(json['notBefore'] as String)
          : null,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      attempt: (json['attempt'] as num?)?.toInt() ?? 0,
      maxRetries: (json['maxRetries'] as num?)?.toInt() ?? 0,
      visibilityTimeout: json['visibilityTimeout'] != null
          ? Duration(milliseconds: (json['visibilityTimeout'] as num).toInt())
          : null,
      queue: json['queue'] as String? ?? 'default',
      meta: (json['meta'] as Map?)?.cast<String, Object?>(),
    );
  }

  @override
  String toString() => jsonEncode(toJson());
}

/// Runtime wrapper containing the envelope plus broker-specific receipt info.
class Delivery {
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

  final Envelope envelope;

  /// Broker specific handle used for ack/nack/extend operations.
  final String receipt;

  /// When the current lease expires (if supported).
  final DateTime? leaseExpiresAt;

  /// Routing metadata resolved for this delivery.
  final RoutingInfo route;
}
