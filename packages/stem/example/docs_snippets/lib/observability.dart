// Observability snippets for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'package:contextual/contextual.dart';
import 'package:stem/stem.dart';

// #region observability-metrics
void configureMetrics() {
  StemMetrics.instance.configure(exporters: [ConsoleMetricsExporter()]);
}
// #endregion observability-metrics

// #region observability-tracing
Stem buildTracedStem(Broker broker, ResultBackend backend, TaskRegistry registry) {
  // Configure OpenTelemetry globally; StemTracer.instance reads from it.
  final _ = StemTracer.instance;
  return Stem(
    broker: broker,
    registry: registry,
    backend: backend,
  );
}
// #endregion observability-tracing

// #region observability-signals
void registerSignals() {
  StemSignals.taskRetry.connect((payload, _) {
    metrics.recordRetry(delay: payload.nextRetryAt.difference(DateTime.now()));
  });

  StemSignals.workerHeartbeat.connect((payload, _) {
    heartbeatGauge.set(1, tags: {'worker': payload.worker.id});
  });
}
// #endregion observability-signals

// #region observability-queue-depth
final queueDepthGauge = GaugeMetric();

void recordQueueDepth(String queue, int depth) {
  queueDepthGauge.set(depth.toDouble(), tags: {'queue': queue});
}
// #endregion observability-queue-depth

// #region observability-logging
void logTaskStart(Envelope envelope) {
  stemLogger.info(
    'Task started',
    Context({'task': envelope.name, 'id': envelope.id}),
  );
}
// #endregion observability-logging

final metrics = MetricsCollector();
final heartbeatGauge = GaugeMetric();

class MetricsCollector {
  void recordRetry({required Duration delay}) {}
}

class GaugeMetric {
  void set(double value, {Map<String, String>? tags}) {}
}

Future<void> main() async {
  configureMetrics();
  registerSignals();

  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<void>(
        name: 'demo.trace',
        entrypoint: (context, args) async {
          print('Tracing demo task');
          return null;
        },
      ),
    );

  final stem = buildTracedStem(
    InMemoryBroker(),
    InMemoryResultBackend(),
    registry,
  );

  logTaskStart(
    Envelope(
      name: 'demo.trace',
      args: const {},
    ),
  );
  await stem.enqueue('demo.trace', args: const {});
}
