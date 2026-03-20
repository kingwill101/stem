import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';

final pingDefinition = TaskDefinition.noArgs<void>(name: 'metrics.ping');

Future<void> main() async {
  final tasks = <TaskHandler<Object?>>[
    FunctionTaskHandler<void>(
      name: pingDefinition.name,
      entrypoint: (context, _) async {
        // Simulate a bit of work.
        await Future<void>.delayed(const Duration(milliseconds: 150));
        context.progress(1.0);
        return null;
      },
    ),
  ];

  final otlpEndpoint = Platform.environment['STEM_OTLP_ENDPOINT'] ??
      'http://localhost:4318/v1/metrics';

  final observability = ObservabilityConfig(
    namespace: 'demo-otel',
    heartbeatInterval: Duration.zero,
    metricExporters: ['otlp:$otlpEndpoint'],
  );

  final client = await StemClient.inMemory(
    tasks: tasks,
  );
  final worker = await client.createWorker(
    workerConfig: const StemWorkerConfig(
      consumerName: 'otel-demo-worker',
      heartbeatTransport: NoopHeartbeatTransport(),
    ).copyWith(
      observability: observability,
    ),
  );

  await worker.start();
  print(
    'Worker started. Streaming metrics to ${observability.metricExporters.first}.',
  );

  Timer.periodic(const Duration(seconds: 1), (_) async {
    await pingDefinition.enqueue(client);
  });
}
