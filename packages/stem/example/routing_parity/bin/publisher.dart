import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';
import 'package:stem_routing_parity_example/routing_demo.dart';

Future<void> main() async {
  final redisUrl = Platform.environment['ROUTING_DEMO_REDIS_URL'] ??
      'redis://localhost:6379/0';

  final routing = buildRoutingRegistry();
  final registry = buildDemoTaskRegistry();

  final broker = await RedisStreamsBroker.connect(
    redisUrl,
    namespace: 'stem-routing-demo',
  );

  final stem = Stem(
    broker: broker,
    registry: registry,
    routing: routing,
  );

  stdout.writeln('Publishing demo tasks using routing parity features...');

  await _enqueueWithRouting(
    stem,
    routing,
    'billing.invoice',
    args: const {'invoiceId': 101},
  );
  await _enqueueWithRouting(
    stem,
    routing,
    'billing.invoice',
    args: const {'invoiceId': 102},
  );

  await _enqueueWithRouting(
    stem,
    routing,
    'reports.generate',
    args: const {'subject': 'Quarterly summary', 'priority': 'low'},
    options: const TaskOptions(priority: 1),
  );
  await _enqueueWithRouting(
    stem,
    routing,
    'reports.generate',
    args: const {'subject': 'Incident post-mortem', 'priority': 'high'},
    options: const TaskOptions(priority: 9),
  );

  await _enqueueWithRouting(
    stem,
    routing,
    'ops.status',
    args: const {'message': 'Maintenance window begins at 02:00 UTC.'},
  );

  stdout
      .writeln('All demo tasks enqueued. Watch the worker output for results.');
  await broker.close();
}

Future<void> _enqueueWithRouting(
  Stem stem,
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

  final id = await stem.enqueue(
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
