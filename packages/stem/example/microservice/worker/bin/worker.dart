import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

const _taskSpecs = <_WorkerTaskSpec>[
  _WorkerTaskSpec(
    name: 'greeting.send',
    queue: 'greetings',
    maxRetries: 5,
    softLimit: Duration(seconds: 10),
    hardLimit: Duration(seconds: 20),
  ),
  _WorkerTaskSpec(
    name: 'customer.followup',
    queue: 'greetings',
    maxRetries: 4,
    softLimit: Duration(seconds: 12),
    hardLimit: Duration(seconds: 22),
  ),
  _WorkerTaskSpec(
    name: 'billing.charge',
    queue: 'billing',
    maxRetries: 5,
    softLimit: Duration(seconds: 12),
    hardLimit: Duration(seconds: 24),
  ),
  _WorkerTaskSpec(
    name: 'billing.settlement',
    queue: 'billing',
    maxRetries: 3,
    softLimit: Duration(seconds: 10),
    hardLimit: Duration(seconds: 18),
  ),
  _WorkerTaskSpec(
    name: 'reports.aggregate',
    queue: 'reporting',
    maxRetries: 2,
    softLimit: Duration(seconds: 12),
    hardLimit: Duration(seconds: 24),
  ),
  _WorkerTaskSpec(
    name: 'reports.publish',
    queue: 'reporting',
    maxRetries: 2,
    softLimit: Duration(seconds: 10),
    hardLimit: Duration(seconds: 18),
  ),
];

final _taskEntrypoints = <String, TaskEntrypoint>{
  'greeting.send': _greetingSendEntrypoint,
  'customer.followup': _customerFollowupEntrypoint,
  'billing.charge': _billingChargeEntrypoint,
  'billing.settlement': _billingSettlementEntrypoint,
  'reports.aggregate': _reportsAggregateEntrypoint,
  'reports.publish': _reportsPublishEntrypoint,
};

Future<void> main(List<String> args) async {
  // #region signing-worker-config
  final config = StemConfig.fromEnvironment();
  // #endregion signing-worker-config
  final broker = await RedisStreamsBroker.connect(
    config.brokerUrl,
    tls: config.tls,
  );
  final backend = config.resultBackendUrl != null
      ? await RedisResultBackend.connect(
          config.resultBackendUrl!,
          tls: config.tls,
        )
      : InMemoryResultBackend();
  // #region signing-worker-signer
  final signer = PayloadSigner.maybe(config.signing);
  // #endregion signing-worker-signer

  final tasks = _taskSpecs.map<TaskHandler<Object?>>((spec) {
    final entrypoint = _taskEntrypoints[spec.name];
    if (entrypoint == null) {
      throw StateError('Missing task entrypoint for ${spec.name}');
    }
    return FunctionTaskHandler<String>(
      name: spec.name,
      entrypoint: entrypoint,
      options: TaskOptions(
        queue: spec.queue,
        maxRetries: spec.maxRetries,
        softTimeLimit: spec.softLimit,
        hardTimeLimit: spec.hardLimit,
      ),
    );
  }).toList(growable: false);

  final observability = ObservabilityConfig.fromEnvironment();
  final configuredWorkerName = Platform.environment['STEM_WORKER_NAME']?.trim();
  final configuredQueue = Platform.environment['STEM_WORKER_QUEUE']?.trim();
  final queue = configuredQueue != null && configuredQueue.isNotEmpty
      ? configuredQueue
      : 'greetings';
  final resolvedWorkerName =
      configuredWorkerName != null && configuredWorkerName.isNotEmpty
          ? configuredWorkerName
          : 'microservice-worker-${Platform.environment['HOSTNAME'] ?? pid}';

  // #region signing-worker-wire
  final worker = Worker(
    broker: broker,
    tasks: tasks,
    backend: backend,
    queue: queue,
    consumerName: resolvedWorkerName,
    concurrency: 4,
    prefetchMultiplier: 2,
    signer: signer,
    observability: observability,
  );
  // #endregion signing-worker-wire

  await worker.start();
  stdout.writeln(
    'Worker "$resolvedWorkerName" listening on queue "$queue"...',
  );

  ProcessSignal.sigint.watch().listen((_) async {
    stdout.writeln('Stopping worker...');
    await worker.shutdown();
    await broker.close();
    if (backend is RedisResultBackend) {
      await backend.close();
    }
    exit(0);
  });

  await Completer<void>().future; // Keep process alive
}

FutureOr<Object?> _greetingSendEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) =>
    _taskEntrypoint('greeting.send', context, args);

FutureOr<Object?> _customerFollowupEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) =>
    _taskEntrypoint('customer.followup', context, args);

FutureOr<Object?> _billingChargeEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) =>
    _taskEntrypoint('billing.charge', context, args);

FutureOr<Object?> _billingSettlementEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) =>
    _taskEntrypoint('billing.settlement', context, args);

FutureOr<Object?> _reportsAggregateEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) =>
    _taskEntrypoint('reports.aggregate', context, args);

FutureOr<Object?> _reportsPublishEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) =>
    _taskEntrypoint('reports.publish', context, args);

FutureOr<Object?> _taskEntrypoint(
  String taskName,
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  final name = (args['name'] as String?) ?? 'friend';
  final fail = args['fail'] == true;
  final delayMsRaw = switch (args['delayMs']) {
    int value => value,
    num value => value.toInt(),
    String value => int.tryParse(value),
    _ => null,
  };
  final delayMs = delayMsRaw == null || delayMsRaw <= 0 ? 500 : delayMsRaw;
  final totalSteps = (delayMs / 200).ceil().clamp(1, 60);
  for (var step = 1; step <= totalSteps; step++) {
    context.heartbeat();
    context.progress(step / totalSteps, data: {
      'step': step,
      'totalSteps': totalSteps,
      'name': name,
    });
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  if (fail) {
    throw StateError(
      'Synthetic failure requested for task=$taskName label=$name',
    );
  }
  final message = 'Processed $taskName for $name';
  stdout.writeln('$message (attempt ${context.attempt})');
  context.progress(1.0, data: {'message': message});
  return message;
}

class _WorkerTaskSpec {
  const _WorkerTaskSpec({
    required this.name,
    required this.queue,
    required this.maxRetries,
    required this.softLimit,
    required this.hardLimit,
  });

  final String name;
  final String queue;
  final int maxRetries;
  final Duration softLimit;
  final Duration hardLimit;
}
