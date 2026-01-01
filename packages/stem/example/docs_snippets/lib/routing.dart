// Routing configuration examples for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

// #region routing-load
Future<RoutingRegistry> loadRouting() async {
  final source = await File('config/routing.yaml').readAsString();
  return RoutingRegistry.fromYaml(source);
}

final registry = RoutingRegistry(
  RoutingConfig(
    defaultQueue: const DefaultQueueConfig(alias: 'default', queue: 'primary'),
    queues: {'primary': QueueDefinition(name: 'primary')},
    routes: [
      RouteDefinition(
        match: RouteMatch.fromJson(const {'task': 'reports.*'}),
        target: RouteTarget(type: 'queue', name: 'primary'),
      ),
    ],
  ),
);
// #endregion routing-load

// #region routing-bootstrap
Future<(Stem, Worker)> bootstrapStem() async {
  final routing = await loadRouting();
  final registry = SimpleTaskRegistry()..register(EmailTask());
  final config = StemConfig.fromEnvironment();
  final subscription = RoutingSubscription(
    queues: config.workerQueues.isEmpty
        ? [config.defaultQueue]
        : config.workerQueues,
    broadcastChannels: config.workerBroadcasts,
  );

  final stem = Stem(
    broker: await RedisStreamsBroker.connect('redis://localhost:6379'),
    registry: registry,
    backend: InMemoryResultBackend(),
    routing: routing,
  );

  final worker = Worker(
    broker: await RedisStreamsBroker.connect('redis://localhost:6379'),
    registry: registry,
    backend: InMemoryResultBackend(),
    subscription: subscription,
  );

  return (stem, worker);
}

class EmailTask extends TaskHandler<void> {
  @override
  String get name => 'email.send';

  @override
  TaskOptions get options => const TaskOptions(queue: 'default');

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {}
}
// #endregion routing-bootstrap

// #region routing-inline
final inlineRegistry = RoutingRegistry(
  RoutingConfig(
    defaultQueue: const DefaultQueueConfig(alias: 'default', queue: 'primary'),
    queues: {'primary': QueueDefinition(name: 'primary')},
    routes: [
      RouteDefinition(
        match: RouteMatch.fromJson(const {'task': 'reports.*'}),
        target: RouteTarget(type: 'queue', name: 'primary'),
      ),
    ],
  ),
);
// #endregion routing-inline

Future<void> main() async {
  final decision = inlineRegistry.resolve(
    RouteRequest(task: 'reports.monthly', headers: const {}),
  );
  print('Inline route target: ${decision.targetName}');

  final file = File('config/routing.yaml');
  if (await file.exists()) {
    final loaded = await loadRouting();
    final loadedDecision = loaded.resolve(
      RouteRequest(task: 'reports.monthly', headers: const {}),
    );
    print('File route target: ${loadedDecision.targetName}');
  } else {
    print('No routing.yaml found; skipping file-based routing demo.');
  }
}
