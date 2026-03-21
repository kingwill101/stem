import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';
import 'package:stem_routing_parity_example/routing_demo.dart';

Future<void> main() async {
  final redisUrl = Platform.environment['ROUTING_DEMO_REDIS_URL'] ??
      'redis://localhost:6379/0';

  final routing = buildRoutingRegistry();
  final tasks = buildDemoTasks();
  final client = await StemClient.fromUrl(
    redisUrl,
    adapters: const [StemRedisAdapter(namespace: 'stem-routing-demo')],
    overrides: const StemStoreOverrides(backend: 'memory://'),
    tasks: tasks,
    routing: routing,
  );

  stdout.writeln('Publishing demo tasks using routing parity features...');

  await _enqueueWithRouting(
    client,
    routing,
    'billing.invoice',
    args: const {'invoiceId': 101},
  );
  await _enqueueWithRouting(
    client,
    routing,
    'billing.invoice',
    args: const {'invoiceId': 102},
  );

  await _enqueueWithRouting(
    client,
    routing,
    'reports.generate',
    args: const {'subject': 'Quarterly summary', 'priority': 'low'},
    options: const TaskOptions(priority: 1),
  );
  await _enqueueWithRouting(
    client,
    routing,
    'reports.generate',
    args: const {'subject': 'Incident post-mortem', 'priority': 'high'},
    options: const TaskOptions(priority: 9),
  );

  await _enqueueWithRouting(
    client,
    routing,
    'ops.status',
    args: const {'message': 'Maintenance window begins at 02:00 UTC.'},
  );

  stdout
      .writeln('All demo tasks enqueued. Watch the worker output for results.');
  await client.close();
}

Future<void> _enqueueWithRouting(
  TaskEnqueuer enqueuer,
  RoutingRegistry routing,
  String name, {
  Map<String, Object?> args = const {},
  Map<String, String> headers = const {},
  TaskOptions options = const TaskOptions(),
  Map<String, Object?> meta = const {},
}) async {
  final decision = routing.resolve(
    RouteRequest(
      task: name,
      headers: headers,
      queue: options.queue,
    ),
  );
  final effectivePriority = decision.effectivePriority(options.priority);
  final computedMeta = {
    'queue': decision.targetName,
    'priority': effectivePriority,
    'targetType': decision.isBroadcast ? 'broadcast' : 'queue',
    ...meta,
  };

  final id = await enqueuer.enqueue(
    name,
    args: args,
    headers: headers,
    options: options,
    meta: computedMeta,
  );

  stdout.writeln(
    '→ $name routed to ${decision.targetName} '
    '(${decision.isBroadcast ? 'broadcast' : 'queue'}, priority $effectivePriority, id=$id)',
  );
}
