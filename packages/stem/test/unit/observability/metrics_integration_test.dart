import 'dart:async';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

class _RecordingMetricsExporter extends MetricsExporter {
  final List<MetricEvent> events = [];

  @override
  void record(MetricEvent event) {
    events.add(event);
  }
}

void main() {
  test('worker emits OpenTelemetry metrics during task execution', () async {
    final exporter = _RecordingMetricsExporter();
    StemMetrics.instance.reset();
    StemMetrics.instance.configure(exporters: [exporter]);

    final broker = InMemoryBroker();
    final backend = InMemoryResultBackend();
    final registry = SimpleTaskRegistry()
      ..register(
        FunctionTaskHandler<void>(
          name: 'metrics.test',
          entrypoint: (context, unusedArgs) async {
            await context.extendLease(const Duration(milliseconds: 10));
            await Future<void>.delayed(const Duration(milliseconds: 20));
            return;
          },
        ),
      );

    final stem = Stem(broker: broker, registry: registry, backend: backend);
    final worker = Worker(
      broker: broker,
      registry: registry,
      backend: backend,
      consumerName: 'metrics-worker',
      heartbeatInterval: const Duration(milliseconds: 25),
      workerHeartbeatInterval: const Duration(milliseconds: 25),
      heartbeatTransport: const NoopHeartbeatTransport(),
    );

    await worker.start();
    final taskId = await stem.enqueue('metrics.test');
    await _waitFor(() async {
      final status = await backend.get(taskId);
      return status?.state == TaskState.succeeded;
    });

    // Allow heartbeat loop to run once more for gauge update.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await worker.shutdown();
    broker.dispose();

    final counters = exporter.events
        .where((event) => event.type == MetricType.counter)
        .map((event) => event.name)
        .toList();
    expect(counters, contains('stem.tasks.started'));
    expect(counters, contains('stem.tasks.succeeded'));

    final histograms = exporter.events
        .where((event) => event.type == MetricType.histogram)
        .map((event) => event.name)
        .toList();
    expect(histograms, contains('stem.task.duration'));

    final gauges = exporter.events
        .where((event) => event.type == MetricType.gauge)
        .toList();
    expect(
      gauges.where((event) => event.name == 'stem.worker.inflight'),
      isNotEmpty,
    );
    expect(
      gauges.where((event) => event.name == 'stem.queue.depth'),
      isNotEmpty,
    );

    final leaseRenewals = exporter.events
        .where((event) => event.type == MetricType.counter)
        .where((event) => event.name == 'stem.lease.renewed')
        .toList();
    expect(leaseRenewals, isNotEmpty);

    final snapshot = StemMetrics.instance.snapshot();
    final counterSnapshot = snapshot['counters'] as List<dynamic>? ?? const [];
    final counterMaps = counterSnapshot
        .whereType<Map<String, Object?>>()
        .toList();
    final started = counterMaps.firstWhere(
      (value) => value['name'] == 'stem.tasks.started',
    );
    expect(started['value'], equals(1));
    final succeeded = counterMaps.firstWhere(
      (value) => value['name'] == 'stem.tasks.succeeded',
    );
    expect(succeeded['value'], equals(1));

    StemMetrics.instance.reset();
    StemMetrics.instance.configure();
  });
}

Future<void> _waitFor(Future<bool> Function() predicate) async {
  const timeout = Duration(seconds: 2);
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('Timed out waiting for condition.');
}
