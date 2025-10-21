import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:glob/glob.dart';
import 'package:yaml/yaml.dart';

/// Canonical representation of routing configuration loaded from YAML or JSON.
///
/// Provides strongly typed access to queue, route, and broadcast definitions
/// while preserving default alias semantics for backwards compatibility.
class RoutingConfig {
  RoutingConfig({
    required DefaultQueueConfig defaultQueue,
    required Map<String, QueueDefinition> queues,
    List<RouteDefinition>? routes,
    Map<String, BroadcastDefinition>? broadcasts,
  })  : defaultQueue = defaultQueue,
        queues = Map.unmodifiable(queues),
        routes = List.unmodifiable(routes ?? const []),
        broadcasts = Map.unmodifiable(broadcasts ?? const {});

  /// Default queue alias configuration.
  final DefaultQueueConfig defaultQueue;

  /// Registered queue definitions keyed by canonical queue name.
  final Map<String, QueueDefinition> queues;

  /// Declarative routing rules evaluated in order of appearance.
  final List<RouteDefinition> routes;

  /// Broadcast channel definitions keyed by logical channel name.
  final Map<String, BroadcastDefinition> broadcasts;

  /// Construct a configuration that mirrors the legacy single queue behaviour.
  factory RoutingConfig.legacy() {
    final defaultQueue = QueueDefinition(name: 'default');
    return RoutingConfig(
      defaultQueue: DefaultQueueConfig(
        alias: 'default',
        queue: defaultQueue.name,
        fallbacks: const [],
      ),
      queues: {defaultQueue.name: defaultQueue},
    );
  }

  /// Parse YAML/JSON encoded configuration.
  factory RoutingConfig.fromYaml(String source) {
    if (source.trim().isEmpty) {
      return RoutingConfig.legacy();
    }
    final decoded = loadYaml(source);
    final jsonSafe = jsonDecode(jsonEncode(decoded));
    if (jsonSafe is! Map<String, dynamic>) {
      throw const FormatException('Routing config must decode to a map.');
    }
    return RoutingConfig.fromJson(jsonSafe);
  }

  /// Parse from a JSON-like map structure (typically decoded YAML/JSON).
  factory RoutingConfig.fromJson(Map<String, Object?> json) {
    final queuesJson = _readMap(json, 'queues');
    final queues = <String, QueueDefinition>{
      for (final entry in queuesJson.entries)
        entry.key: QueueDefinition.fromJson(
          entry.key,
          _requireMap(entry.value, context: 'queues["${entry.key}"]'),
        ),
    };
    if (queues.isEmpty) {
      final defaultQueue = QueueDefinition(name: 'default');
      queues[defaultQueue.name] = defaultQueue;
    }

    final defaultQueue = DefaultQueueConfig.fromJson(
      json['default_queue'] ?? json['defaultQueue'],
      queueLookup: queues.keys,
    );

    final broadcastsJson = _readMap(json, 'broadcasts');
    final broadcasts = <String, BroadcastDefinition>{
      for (final entry in broadcastsJson.entries)
        entry.key: BroadcastDefinition.fromJson(
          entry.key,
          _requireMap(entry.value, context: 'broadcasts["${entry.key}"]'),
        ),
    };

    final routesJson = _readList(json, 'routes');
    final routes = [
      for (var i = 0; i < routesJson.length; i++)
        RouteDefinition.fromJson(
          _requireMap(routesJson[i], context: 'routes[$i]'),
        ),
    ];

    return RoutingConfig(
      defaultQueue: defaultQueue,
      queues: queues,
      routes: routes,
      broadcasts: broadcasts,
    );
  }

  Map<String, Object?> toJson() => {
        'defaultQueue': defaultQueue.toJson(),
        'queues': queues.map((key, value) => MapEntry(key, value.toJson())),
        if (routes.isNotEmpty)
          'routes': routes.map((route) => route.toJson()).toList(),
        if (broadcasts.isNotEmpty)
          'broadcasts':
              broadcasts.map((key, value) => MapEntry(key, value.toJson())),
      };
}

/// Default queue alias configuration tying `alias` to a canonical queue name.
class DefaultQueueConfig {
  const DefaultQueueConfig({
    required this.alias,
    required this.queue,
    this.fallbacks = const [],
  });

  /// Alias used by legacy code when referencing the default queue.
  final String alias;

  /// Canonical queue name resolved by the alias.
  final String queue;

  /// Additional queue aliases consulted when the primary queue is unavailable.
  final List<String> fallbacks;

  factory DefaultQueueConfig.fromJson(
    Object? value, {
    required Iterable<String> queueLookup,
  }) {
    if (value == null) {
      return DefaultQueueConfig(
        alias: 'default',
        queue: _resolveQueueOrFallback('default', queueLookup),
      );
    }
    if (value is String && value.trim().isNotEmpty) {
      final queue = value.trim();
      final canonical = _resolveQueueOrFallback(queue, queueLookup);
      return DefaultQueueConfig(
        alias: 'default',
        queue: canonical,
      );
    }
    final map =
        _requireMap(value, context: 'default_queue').map((key, val) => MapEntry(
              key.toString(),
              val,
            ));
    final alias = (map['alias'] as String?)?.trim().isNotEmpty == true
        ? (map['alias'] as String).trim()
        : 'default';
    final queueValue = (map['queue'] as String?)?.trim().isNotEmpty == true
        ? map['queue'] as String
        : alias;
    final queue = _resolveQueueOrFallback(queueValue, queueLookup);
    final fallbackValues =
        _readStringList(map['fallbacks']) ?? const <String>[];
    final fallbacks = [
      for (final fallback in fallbackValues)
        _resolveQueueOrFallback(fallback, queueLookup),
    ];
    return DefaultQueueConfig(
      alias: alias,
      queue: queue,
      fallbacks: fallbacks,
    );
  }

  Map<String, Object?> toJson() => {
        'alias': alias,
        'queue': queue,
        if (fallbacks.isNotEmpty) 'fallbacks': fallbacks,
      };
}

/// Detailed queue definition with optional routing metadata.
class QueueDefinition {
  QueueDefinition({
    required this.name,
    this.exchange,
    this.routingKey,
    QueuePriorityRange? priorityRange,
    List<QueueBinding>? bindings,
    Map<String, Object?>? metadata,
  })  : priorityRange = priorityRange ?? QueuePriorityRange.standard,
        bindings = List.unmodifiable(bindings ?? const []),
        metadata = Map.unmodifiable(metadata ?? const {});

  final String name;
  final String? exchange;
  final String? routingKey;
  final QueuePriorityRange priorityRange;
  final List<QueueBinding> bindings;
  final Map<String, Object?> metadata;

  factory QueueDefinition.fromJson(String name, Map<String, Object?> json) {
    final exchange = (json['exchange'] as String?)?.trim();
    final routingKey = (json['routing_key'] ?? json['routingKey']) as String?;
    final bindingsJson = _readList(json, 'bindings');
    final bindings = [
      for (var i = 0; i < bindingsJson.length; i++)
        QueueBinding.fromJson(
          _requireMap(bindingsJson[i], context: 'queues["$name"].bindings[$i]'),
        ),
    ];
    final priorityValue = json['priority_range'] ?? json['priorityRange'];
    final priorityRange = priorityValue != null
        ? QueuePriorityRange.fromJson(priorityValue)
        : QueuePriorityRange.standard;
    final metadata = _readMap(json, 'meta');
    return QueueDefinition(
      name: name,
      exchange: exchange?.isEmpty == true ? null : exchange,
      routingKey:
          routingKey?.toString().trim().isEmpty == true ? null : routingKey,
      priorityRange: priorityRange,
      bindings: bindings,
      metadata: metadata,
    );
  }

  Map<String, Object?> toJson() => {
        if (exchange != null) 'exchange': exchange,
        if (routingKey != null) 'routingKey': routingKey,
        'priorityRange': priorityRange.toJson(),
        if (bindings.isNotEmpty)
          'bindings': bindings.map((binding) => binding.toJson()).toList(),
        if (metadata.isNotEmpty) 'meta': metadata,
      };
}

/// Priority range constraint applied to a queue definition.
class QueuePriorityRange {
  const QueuePriorityRange({required this.min, required this.max})
      : assert(min <= max, 'min priority must be <= max priority');

  static const QueuePriorityRange standard = QueuePriorityRange(min: 0, max: 9);

  final int min;
  final int max;

  factory QueuePriorityRange.fromJson(Object? value) {
    if (value is List && value.length == 2) {
      final min = _parseInt(value[0], context: 'priority_range[0]');
      final max = _parseInt(value[1], context: 'priority_range[1]');
      if (min > max) {
        throw const FormatException(
          'priority_range min must be less than or equal to max.',
        );
      }
      return QueuePriorityRange(min: min, max: max);
    }
    if (value is Map) {
      final map = _asStringKeyedMap(value);
      final min = _parseInt(map['min'], context: 'priority_range.min');
      final max = _parseInt(map['max'], context: 'priority_range.max');
      if (min > max) {
        throw const FormatException(
          'priority_range min must be less than or equal to max.',
        );
      }
      return QueuePriorityRange(min: min, max: max);
    }
    throw const FormatException(
      'priority_range must be a 2 element list or object with "min"/"max".',
    );
  }

  Map<String, int> toJson() => {'min': min, 'max': max};

  int clamp(int value) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }
}

/// Binding between a routing key (and optional headers) and a queue.
class QueueBinding {
  QueueBinding({
    required this.routingKey,
    Map<String, String>? headers,
    this.weight,
  }) : headers = Map.unmodifiable(headers ?? const {});

  final String routingKey;
  final Map<String, String> headers;
  final int? weight;

  factory QueueBinding.fromJson(Map<String, Object?> json) {
    final routingKey = (json['routing_key'] ?? json['routingKey']) as String?;
    if (routingKey == null || routingKey.trim().isEmpty) {
      throw const FormatException('binding requires routing_key.');
    }
    final headers = _readStringMap(json['headers']);
    final weight = json['weight'];
    return QueueBinding(
      routingKey: routingKey.trim(),
      headers: headers ?? const {},
      weight: weight is num ? weight.toInt() : null,
    );
  }

  Map<String, Object?> toJson() => {
        'routingKey': routingKey,
        if (headers.isNotEmpty) 'headers': headers,
        if (weight != null) 'weight': weight,
      };
}

/// Broadcast channel declaration.
class BroadcastDefinition {
  BroadcastDefinition({
    required this.name,
    this.durability,
    this.delivery,
    Map<String, Object?>? metadata,
  }) : metadata = Map.unmodifiable(metadata ?? const {});

  final String name;
  final String? durability;
  final String? delivery;
  final Map<String, Object?> metadata;

  factory BroadcastDefinition.fromJson(
    String name,
    Map<String, Object?> json,
  ) {
    final durability = (json['durability'] as String?)?.trim();
    final delivery = (json['delivery'] as String?)?.trim();
    final metadata = _readMap(json, 'meta');
    return BroadcastDefinition(
      name: name,
      durability: durability?.isEmpty == true ? null : durability,
      delivery: delivery?.isEmpty == true ? null : delivery,
      metadata: metadata,
    );
  }

  Map<String, Object?> toJson() => {
        if (durability != null) 'durability': durability,
        if (delivery != null) 'delivery': delivery,
        if (metadata.isNotEmpty) 'meta': metadata,
      };
}

/// Declarative routing rule mapping match criteria to targets.
class RouteDefinition {
  RouteDefinition({
    required this.match,
    required this.target,
    this.priorityOverride,
    Map<String, Object?>? options,
  }) : options = Map.unmodifiable(options ?? const {});

  final RouteMatch match;
  final RouteTarget target;
  final int? priorityOverride;
  final Map<String, Object?> options;

  factory RouteDefinition.fromJson(Map<String, Object?> json) {
    final match = RouteMatch.fromJson(
      _requireMap(json['match'], context: 'route.match'),
    );
    final target = RouteTarget.fromJson(
      _requireMap(json['target'], context: 'route.target'),
    );
    final priority = json['priority_override'] ?? json['priorityOverride'];
    final options = _readMap(json, 'options');
    return RouteDefinition(
      match: match,
      target: target,
      priorityOverride: priority is num ? priority.toInt() : null,
      options: options,
    );
  }

  Map<String, Object?> toJson() => {
        'match': match.toJson(),
        'target': target.toJson(),
        if (priorityOverride != null) 'priorityOverride': priorityOverride,
        if (options.isNotEmpty) 'options': options,
      };
}

/// Routing match criteria with optional task glob, headers, or queue override.
class RouteMatch {
  RouteMatch({
    List<Glob>? taskGlobs,
    Map<String, String>? headers,
    this.queueOverride,
  })  : taskGlobs = taskGlobs == null ? null : List.unmodifiable(taskGlobs),
        headers = Map.unmodifiable(headers ?? const {});

  final List<Glob>? taskGlobs;
  final Map<String, String> headers;
  final String? queueOverride;

  factory RouteMatch.fromJson(Map<String, Object?> json) {
    final tasks = _normalizeTaskPatterns(json['task']);
    final headers = _readStringMap(json['headers']);
    final queueOverride =
        (json['queue_override'] ?? json['queueOverride']) as String?;
    return RouteMatch(
      taskGlobs: tasks,
      headers: headers ?? const {},
      queueOverride:
          queueOverride?.trim().isEmpty == true ? null : queueOverride?.trim(),
    );
  }

  Map<String, Object?> toJson() {
    Object? serializedTask;
    if (taskGlobs != null) {
      if (taskGlobs!.length == 1) {
        serializedTask = taskGlobs!.first.pattern;
      } else {
        serializedTask = taskGlobs!.map((glob) => glob.pattern).toList();
      }
    }
    return {
      if (serializedTask != null) 'task': serializedTask,
      if (headers.isNotEmpty) 'headers': headers,
      if (queueOverride != null) 'queueOverride': queueOverride,
    };
  }
}

/// Route target describing queue or broadcast destination.
class RouteTarget {
  RouteTarget({
    required this.type,
    required this.name,
  });

  final String type;
  final String name;

  factory RouteTarget.fromJson(Map<String, Object?> json) {
    final type = (json['type'] as String?)?.trim() ?? 'queue';
    final name = (json['name'] as String?)?.trim();
    if (name == null || name.isEmpty) {
      throw const FormatException('route target requires name.');
    }
    return RouteTarget(
      type: type.isEmpty ? 'queue' : type,
      name: name,
    );
  }

  Map<String, Object?> toJson() => {
        'type': type,
        'name': name,
      };
}

List<Glob>? _normalizeTaskPatterns(Object? value) {
  if (value == null) return null;
  final patterns = <String>[];
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('route match task glob must not be empty.');
    }
    patterns.add(trimmed);
  } else if (value is List) {
    for (final entry in value) {
      if (entry == null) continue;
      final trimmed = entry.toString().trim();
      if (trimmed.isEmpty) {
        throw const FormatException(
          'route match task glob list contains an empty pattern.',
        );
      }
      patterns.add(trimmed);
    }
    if (patterns.isEmpty) {
      throw const FormatException(
        'route match task glob list must contain at least one pattern.',
      );
    }
  } else {
    throw const FormatException('route match task must be string or list.');
  }
  return patterns.map((pattern) => Glob(pattern)).toList();
}

String _resolveQueueOrFallback(
  String candidate,
  Iterable<String> knownQueues,
) {
  final lookup = knownQueues.firstWhereOrNull((queue) => queue == candidate);
  if (lookup == null) {
    throw FormatException(
      'Referenced queue "$candidate" is not defined in routing config.',
    );
  }
  return lookup;
}

Map<String, Object?> _readMap(Map<String, Object?> source, String key) {
  final value = source[key] ?? source[_camelToSnake(key)];
  if (value == null) return const {};
  return _requireMap(value, context: key);
}

Map<String, Object?> _requireMap(
  Object? value, {
  required String context,
}) {
  if (value == null) {
    throw FormatException('$context must be a map.');
  }
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return _asStringKeyedMap(value);
  }
  throw FormatException('$context must be a map.');
}

List<Object?> _readList(Map<String, Object?> source, String key) {
  final value = source[key] ?? source[_camelToSnake(key)];
  if (value == null) return const [];
  if (value is List<Object?>) return value;
  if (value is List) return List<Object?>.from(value);
  throw FormatException('$key must be a list.');
}

List<String>? _readStringList(Object? value) {
  if (value == null) return null;
  if (value is List) {
    return value
        .map((element) => element?.toString())
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  throw const FormatException('Expected list of strings.');
}

Map<String, String>? _readStringMap(Object? value) {
  if (value == null) return null;
  if (value is Map) {
    final map = <String, String>{};
    value.forEach((key, val) {
      if (key == null || val == null) return;
      map[key.toString()] = val.toString();
    });
    return map;
  }
  throw const FormatException('Expected map of strings.');
}

int _parseInt(Object? value, {required String context}) {
  if (value is num) return value.toInt();
  if (value is String && value.trim().isNotEmpty) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) return parsed;
  }
  throw FormatException('$context must be an integer.');
}

Map<String, Object?> _asStringKeyedMap(Map<dynamic, dynamic> source) {
  return source.map((key, value) => MapEntry(key.toString(), value));
}

String _camelToSnake(String value) {
  final buffer = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    final codeUnit = value.codeUnitAt(i);
    final char = String.fromCharCode(codeUnit);
    if (_isUppercase(codeUnit) && i > 0) {
      buffer.write('_');
    }
    buffer.write(char.toLowerCase());
  }
  return buffer.toString();
}

bool _isUppercase(int codeUnit) => codeUnit >= 0x41 && codeUnit <= 0x5A; // A-Z
