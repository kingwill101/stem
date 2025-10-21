import 'routing_config.dart';

/// Describes the routing decision for an enqueue request.
class RouteDecision {
  RouteDecision.queue({
    required QueueDefinition queue,
    String? selectedAlias,
    RouteDefinition? route,
    int? priorityOverride,
    Iterable<QueueDefinition> fallbackQueues = const [],
  })  : type = RouteDecisionType.queue,
        queue = queue,
        broadcast = null,
        route = route,
        priorityOverride = priorityOverride,
        selectedQueueAlias = selectedAlias ?? queue.name,
        fallbackQueues = List.unmodifiable(fallbackQueues),
        broadcastChannel = null;

  RouteDecision.broadcast({
    required BroadcastDefinition broadcast,
    RouteDefinition? route,
    int? priorityOverride,
  })  : type = RouteDecisionType.broadcast,
        queue = null,
        broadcast = broadcast,
        route = route,
        priorityOverride = priorityOverride,
        selectedQueueAlias = null,
        fallbackQueues = const [],
        broadcastChannel = broadcast.name;

  /// The type of target selected for the route.
  final RouteDecisionType type;

  /// Queue metadata when the decision targets a queue.
  final QueueDefinition? queue;

  /// Broadcast metadata when the decision targets a broadcast channel.
  final BroadcastDefinition? broadcast;

  /// Matched route configuration, if any.
  final RouteDefinition? route;

  /// Priority override supplied by the matched route.
  final int? priorityOverride;

  /// Alias used to select the resolved queue (defaults to queue name).
  final String? selectedQueueAlias;

  /// Additional fallback queues for the selection (primarily for default queue aliasing).
  final List<QueueDefinition> fallbackQueues;

  /// Broadcast channel name when targeting a broadcast.
  final String? broadcastChannel;

  /// Whether this decision targets a broadcast channel.
  bool get isBroadcast => type == RouteDecisionType.broadcast;

  /// Canonical target name (queue or broadcast channel).
  String get targetName => isBroadcast ? broadcast!.name : queue!.name;
}

/// Distinguishes queue vs broadcast routing decisions.
enum RouteDecisionType { queue, broadcast }

/// Immutable request used when resolving routing decisions.
class RouteRequest {
  RouteRequest({
    required this.task,
    Map<String, String>? headers,
    String? queue,
  })  : headers = Map.unmodifiable(
          headers == null ? const {} : Map<String, String>.from(headers),
        ),
        queue = queue?.trim().isNotEmpty == true ? queue!.trim() : null;

  /// Task name being enqueued.
  final String task;

  /// Header values attached to the envelope.
  final Map<String, String> headers;

  /// Explicit queue requested by the producer (alias or canonical name).
  final String? queue;
}

/// Registry that resolves routing configuration into queue/broadcast decisions.
class RoutingRegistry {
  RoutingRegistry(this.config) : _queueAliases = _buildAliasIndex(config) {
    _defaultQueue = _getQueue(config.defaultQueue.queue);
    _defaultFallbackQueues = List.unmodifiable(
      _buildDefaultFallbacks(config.defaultQueue.fallbacks),
    );
    _validateConfig();
  }

  /// Build a registry from a YAML configuration string.
  factory RoutingRegistry.fromYaml(String source) =>
      RoutingRegistry(RoutingConfig.fromYaml(source));

  /// Routing configuration backing this registry.
  final RoutingConfig config;

  late final QueueDefinition _defaultQueue;
  late final List<QueueDefinition> _defaultFallbackQueues;
  final Map<String, String> _queueAliases;
  final Map<RouteMatch, String> _matchQueueOverrides = Map.identity();
  final Map<RouteDefinition, QueueDefinition> _routeQueueTargets =
      Map.identity();
  final Map<RouteDefinition, BroadcastDefinition> _routeBroadcastTargets =
      Map.identity();
  final Map<String, QueueDefinition> _dynamicQueues = {};

  /// Resolve a routing decision for the provided [request].
  RouteDecision resolve(RouteRequest request) {
    String? requestedAlias = request.queue;
    String? resolvedRequestedQueue;
    if (requestedAlias != null) {
      resolvedRequestedQueue = _resolveQueueName(
        requestedAlias,
        context: 'enqueue request queue',
      );
    }

    for (final route in config.routes) {
      if (_matchesRoute(
        route,
        taskName: request.task,
        headers: request.headers,
        resolvedRequestedQueue: resolvedRequestedQueue,
      )) {
        return _decisionFromRoute(route);
      }
    }

    final queue = resolvedRequestedQueue != null
        ? _getQueue(resolvedRequestedQueue)
        : _defaultQueue;
    final alias = resolvedRequestedQueue != null
        ? requestedAlias
        : config.defaultQueue.alias;
    final fallbacks = resolvedRequestedQueue != null
        ? const <QueueDefinition>[]
        : _defaultFallbackQueues;
    return RouteDecision.queue(
      queue: queue,
      selectedAlias: alias,
      route: null,
      priorityOverride: null,
      fallbackQueues: fallbacks,
    );
  }

  /// Retrieve queue metadata by alias or canonical name.
  QueueDefinition queueForAlias(String alias) {
    final resolved = _resolveQueueName(alias, context: 'queue lookup');
    return _getQueue(resolved);
  }

  /// Lookup broadcast metadata by channel name.
  BroadcastDefinition? broadcast(String channel) => config.broadcasts[channel];

  bool _matchesRoute(
    RouteDefinition route, {
    required String taskName,
    required Map<String, String> headers,
    String? resolvedRequestedQueue,
  }) {
    final match = route.match;

    final expectedQueue = _matchQueueOverrides[match];
    if (expectedQueue != null) {
      if (resolvedRequestedQueue == null ||
          resolvedRequestedQueue != expectedQueue) {
        return false;
      }
    }

    if (match.taskGlobs != null && match.taskGlobs!.isNotEmpty) {
      final matched = match.taskGlobs!.any((glob) => glob.matches(taskName));
      if (!matched) return false;
    }

    if (match.headers.isNotEmpty) {
      for (final entry in match.headers.entries) {
        final headerValue = headers[entry.key];
        if (headerValue != entry.value) return false;
      }
    }

    return true;
  }

  RouteDecision _decisionFromRoute(RouteDefinition route) {
    final type = route.target.type.toLowerCase();
    if (type == 'broadcast') {
      final broadcast = _routeBroadcastTargets[route]!;
      return RouteDecision.broadcast(
        broadcast: broadcast,
        route: route,
        priorityOverride: route.priorityOverride,
      );
    }
    if (type != 'queue') {
      throw FormatException(
        'Unsupported route target type "${route.target.type}".',
      );
    }
    final queue = _routeQueueTargets[route]!;
    return RouteDecision.queue(
      queue: queue,
      selectedAlias: route.target.name,
      route: route,
      priorityOverride: route.priorityOverride,
      fallbackQueues: const [],
    );
  }

  void _validateConfig() {
    for (final route in config.routes) {
      final match = route.match;
      if (match.queueOverride != null) {
        final resolved = _resolveQueueName(
          match.queueOverride!,
          context: 'route.match.queue_override',
        );
        _matchQueueOverrides[match] = resolved;
      }

      final type = route.target.type.toLowerCase();
      if (type == 'queue') {
        final resolved = _resolveQueueName(
          route.target.name,
          context: 'route.target',
        );
        _routeQueueTargets[route] = _getQueue(resolved);
      } else if (type == 'broadcast') {
        final broadcast = config.broadcasts[route.target.name];
        if (broadcast == null) {
          throw FormatException(
            'Route target references undefined broadcast "${route.target.name}".',
          );
        }
        _routeBroadcastTargets[route] = broadcast;
      } else {
        throw FormatException(
          'Unsupported route target type "${route.target.type}".',
        );
      }
    }
  }

  QueueDefinition _getQueue(String name) {
    return config.queues[name] ??
        _dynamicQueues.putIfAbsent(name, () => QueueDefinition(name: name));
  }

  List<QueueDefinition> _buildDefaultFallbacks(
    List<String> fallbackNames,
  ) {
    final seen = <String>{};
    final fallbacks = <QueueDefinition>[];
    for (final entry in fallbackNames) {
      final resolved = _resolveQueueName(
        entry,
        context: 'default_queue.fallbacks',
      );
      if (resolved == _defaultQueue.name) continue;
      if (seen.add(resolved)) {
        fallbacks.add(_getQueue(resolved));
      }
    }
    return fallbacks;
  }

  static Map<String, String> _buildAliasIndex(RoutingConfig config) {
    final aliases = <String, String>{};

    void addAlias(String alias, String queue) {
      final normalized = alias.trim();
      if (normalized.isEmpty) return;
      final existing = aliases[normalized];
      if (existing != null && existing != queue) {
        throw FormatException(
          'Queue alias "$normalized" maps to multiple queues '
          '("$existing" vs "$queue").',
        );
      }
      aliases[normalized] = queue;
    }

    for (final entry in config.queues.entries) {
      addAlias(entry.key, entry.key);
    }

    addAlias(config.defaultQueue.alias, config.defaultQueue.queue);
    addAlias('default', config.defaultQueue.queue);

    for (final fallback in config.defaultQueue.fallbacks) {
      addAlias(fallback, fallback);
    }

    return aliases;
  }

  String _resolveQueueName(
    String value, {
    String? context,
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw FormatException(
        'Queue name must not be empty${context != null ? ' ($context)' : ''}.',
      );
    }
    final resolved = _queueAliases[trimmed];
    if (resolved != null) {
      return resolved;
    }
    if (config.queues.containsKey(trimmed)) {
      return trimmed;
    }
    return trimmed;
  }
}
