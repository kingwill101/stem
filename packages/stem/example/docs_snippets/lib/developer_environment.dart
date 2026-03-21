// Infrastructure bootstrap examples for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

// #region dev-env-bootstrap
Future<Bootstrap> bootstrapStem(List<TaskHandler<Object?>> tasks) async {
  // #region dev-env-config
  final config = StemConfig.fromEnvironment(Platform.environment);
  // #endregion dev-env-config

  // #region dev-env-adapters
  final stack = StemStack.fromUrl(
    config.brokerUrl,
    adapters: const [StemRedisAdapter()],
    overrides: StemStoreOverrides(
      backend: _resolveRedisUrl(config.brokerUrl, config.resultBackendUrl, 1),
      revoke: _resolveRedisUrl(config.brokerUrl, config.revokeStoreUrl, 2),
    ),
    requireRevokeStore: true,
  );
  final revokeStore = await stack.revokeStore!.create();
  final routing = await _loadRoutingRegistry(config);
  final rateLimiter = await connectRateLimiter(config);
  // #endregion dev-env-adapters

  // #region dev-env-stem
  final client = await stack.createClient(
    tasks: tasks,
    routing: routing,
  );
  // #endregion dev-env-stem

  // #region dev-env-worker
  final subscription = _buildSubscription(config);
  final worker = await client.createWorker(
    workerConfig: StemWorkerConfig(
      revokeStore: revokeStore,
      rateLimiter: rateLimiter,
      queue: config.defaultQueue,
      subscription: subscription,
      concurrency: 8,
      autoscale: const WorkerAutoscaleConfig(
        enabled: true,
        minConcurrency: 2,
        maxConcurrency: 16,
        backlogPerIsolate: 2.0,
        idlePeriod: Duration(seconds: 45),
      ),
    ),
  );
  // #endregion dev-env-worker

  return Bootstrap(
    client: client,
    worker: worker,
    config: config,
    rateLimiter: rateLimiter,
  );
}

class Bootstrap {
  Bootstrap({
    required this.client,
    required this.worker,
    required this.config,
    required this.rateLimiter,
  });

  final StemClient client;
  final Worker worker;
  final StemConfig config;
  final RateLimiter? rateLimiter;
}
// #endregion dev-env-bootstrap

// #region dev-env-canvas
Future<void> runCanvasFlows(
  Bootstrap bootstrap,
  List<TaskHandler<Object?>> tasks,
) async {
  final canvas = bootstrap.client.createCanvas(tasks: tasks);

  final ids = await canvas.group([
    task('media.resize', args: {'file': 'hero.png'}),
    task('media.resize', args: {'file': 'thumb.png'}),
  ], groupId: 'image-assets');

  final chordId = await canvas.chord(
    body: [
      task('reports.render', args: {'week': '2024-W28'}),
      task('reports.render', args: {'week': '2024-W29'}),
    ],
    callback: task(
      'billing.email-receipt',
      args: {'to': 'finance@example.com'},
      options: const TaskOptions(queue: 'emails'),
    ),
  );

  print('Group dispatched: $ids');
  print('Chord callback task id: $chordId');
}
// #endregion dev-env-canvas

// #region dev-env-status
Future<void> inspectChordStatus(String chordId) async {
  final config = StemConfig.fromEnvironment(Platform.environment);
  final client = await StemClient.fromUrl(
    config.brokerUrl,
    adapters: const [StemRedisAdapter()],
    overrides: StemStoreOverrides(
      backend: _resolveRedisUrl(
        config.brokerUrl,
        config.resultBackendUrl,
        1,
      ),
    ),
  );
  final status = await client.getTaskStatus(chordId);
  print('Chord completion state: ${status?.state}');
  await client.close();
}
// #endregion dev-env-status

// #region dev-env-signals
void installSignalHandlers() {
  StemSignals.taskSucceeded.connect((payload, _) {
    if (payload.taskName == 'reports.render') {
      print('Report ${payload.taskId} succeeded');
    }
  });

  StemSignals.workerReady.connect((payload, _) {
    print(
      'Worker ${payload.worker.id} ready '
      '(queues=${payload.worker.queues.join(",")})',
    );
  });
}
// #endregion dev-env-signals

Future<RoutingRegistry> _loadRoutingRegistry(StemConfig config) async {
  final path = config.routingConfigPath;
  if (path == null || path.isEmpty) {
    return RoutingRegistry(RoutingConfig.legacy());
  }
  final source = await File(path).readAsString();
  return RoutingRegistry.fromYaml(source);
}

RoutingSubscription _buildSubscription(StemConfig config) {
  if (config.workerQueues.isNotEmpty || config.workerBroadcasts.isNotEmpty) {
    return RoutingSubscription(
      queues: config.workerQueues,
      broadcastChannels: config.workerBroadcasts,
    );
  }
  return RoutingSubscription.singleQueue(config.defaultQueue);
}

String _resolveRedisUrl(String brokerUrl, String? override, int db) {
  if (override != null && override.trim().isNotEmpty) return override;
  final parsed = Uri.parse(brokerUrl);
  final resolved = parsed.replace(pathSegments: [db.toString()]);
  return resolved.toString();
}

Future<RateLimiter?> connectRateLimiter(StemConfig config) async {
  return null;
}

Future<void> main() async {
  if (!Platform.environment.containsKey('STEM_BROKER_URL')) {
    print('Set STEM_BROKER_URL to run the developer environment demo.');
    return;
  }

  final tasks = <TaskHandler<Object?>>[
    FunctionTaskHandler<String>(
      name: 'media.resize',
      entrypoint: (context, args) async {
        final file = args['file'] as String? ?? 'asset.png';
        print('Resized $file');
        return file;
      },
    ),
    FunctionTaskHandler<String>(
      name: 'reports.render',
      entrypoint: (context, args) async {
        final week = args['week'] as String? ?? '2024-W01';
        print('Rendered report $week');
        return week;
      },
    ),
    FunctionTaskHandler<void>(
      name: 'billing.email-receipt',
      entrypoint: (context, args) async {
        final to = args['to'] as String? ?? 'ops@example.com';
        print('Queued receipt email to $to');
        return null;
      },
      options: const TaskOptions(queue: 'emails'),
    ),
  ];

  installSignalHandlers();
  final bootstrap = await bootstrapStem(tasks);
  await bootstrap.worker.start();
  await runCanvasFlows(bootstrap, tasks);
  await Future<void>.delayed(const Duration(seconds: 1));
  await bootstrap.worker.shutdown();
  await bootstrap.client.close();
}
