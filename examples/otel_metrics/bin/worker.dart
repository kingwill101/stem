import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';

Future<void> main() async {
  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<void>(
        name: 'metrics.ping',
        entrypoint: (context, _) async {
          // Simulate a bit of work.
          await Future<void>.delayed(const Duration(milliseconds: 150));
          context.progress(1.0);
          return null;
        },
      ),
    );

  final broker = InMemoryRedisBroker();
  final backend = InMemoryResultBackend();

  final otlpEndpoint = Platform.environment['STEM_OTLP_ENDPOINT'] ??
      'http://localhost:4318/v1/metrics';

  final observability = ObservabilityConfig(
    namespace: 'demo-otel',
    heartbeatInterval: Duration.zero,
    metricExporters: ['otlp:$otlpEndpoint'],
  );

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    consumerName: 'otel-demo-worker',
    observability: observability,
    heartbeatTransport: const NoopHeartbeatTransport(),
  );

  final stem = Stem(broker: broker, registry: registry, backend: backend);

  await worker.start();
  print(
    'Worker started. Streaming metrics to ${observability.metricExporters.first}.',
  );

  Timer.periodic(const Duration(seconds: 1), (_) async {
    await stem.enqueue('metrics.ping');
  });
}
