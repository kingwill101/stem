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

  final backend = InMemoryResultBackend();
  final subscription = RoutingSubscription(
    queues: routing.config.queues.keys.toList(growable: false),
    broadcastChannels: routing.config.broadcasts.keys.toList(growable: false),
  );

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    queue: 'standard',
    subscription: subscription,
    concurrency: 2,
    prefetch: 4,
  );

  await worker.start();
  stdout.writeln(
    'Routing parity worker online. Queues=${worker.subscriptionQueues} '
    'Broadcasts=${worker.subscriptionBroadcasts}',
  );

  Future<void> shutdown() async {
    stdout.writeln('Shutting down worker...');
    await worker.shutdown(mode: WorkerShutdownMode.warm);
    await broker.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen((_) => shutdown());
  ProcessSignal.sigterm.watch().listen((_) => shutdown());
}
