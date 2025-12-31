import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    StemMetrics.instance
      ..reset()
      ..configure();
  });

  test('metrics counter aggregates by name and tags', () {
    final metrics = StemMetrics.instance
      ..increment('stem.tasks.succeeded', tags: {'task': 'foo'})
      ..increment('stem.tasks.succeeded', tags: {'task': 'foo'})
      ..increment('stem.tasks.failed', tags: {'task': 'foo'});

    final snapshot = metrics.snapshot();
    final counters = (snapshot['counters'] as List<dynamic>? ?? const [])
        .whereType<Map<String, Object?>>()
        .toList();
    final succeeded = counters.firstWhere(
      (c) => c['name'] == 'stem.tasks.succeeded',
    );
    expect(succeeded['value'], equals(2));
  });

  test('histogram aggregates duration statistics', () {
    final metrics = StemMetrics.instance
      ..recordDuration(
        'stem.task.duration',
        const Duration(milliseconds: 100),
        tags: const {'task': 'foo'},
      )
      ..recordDuration(
        'stem.task.duration',
        const Duration(milliseconds: 250),
        tags: const {'task': 'foo'},
      );

    final snapshot = metrics.snapshot();
    final histograms = (snapshot['histograms'] as List<dynamic>? ?? const [])
        .whereType<Map<String, Object?>>()
        .toList();
    final entry = histograms.firstWhere(
      (c) => c['name'] == 'stem.task.duration',
    );

    expect(entry['count'], equals(2));
    expect(entry['min'], closeTo(100, 0.001));
    expect(entry['max'], closeTo(250, 0.001));
    expect(entry['avg'], closeTo(175, 0.001));
  });

  test('gauge tracks latest value and timestamp', () async {
    final metrics = StemMetrics.instance..setGauge('stem.queue.depth', 15);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    metrics.setGauge('stem.queue.depth', 42);

    final snapshot = metrics.snapshot();
    final gauges = (snapshot['gauges'] as List<dynamic>? ?? const [])
        .whereType<Map<String, Object?>>()
        .toList();
    final gauge = gauges.singleWhere((g) => g['name'] == 'stem.queue.depth');

    expect(gauge['value'], equals(42));
    final updatedAt = gauge['updatedAt'] as String?;
    expect(updatedAt, isNotNull);
    expect(DateTime.parse(updatedAt!), isA<DateTime>());
  });

  test('ConsoleMetricsExporter writes JSON lines to provided sink', () {
    final buffer = StringBuffer();
    final exporter = ConsoleMetricsExporter(sink: buffer);
    final event = MetricEvent(
      type: MetricType.counter,
      name: 'stem.tasks.succeeded',
      value: 1,
      tags: const {'queue': 'default'},
    );

    exporter.record(event);

    expect(buffer.toString(), contains('"stem.tasks.succeeded"'));
  });

  test('PrometheusMetricsExporter renders aggregated samples', () {
    final exporter = PrometheusMetricsExporter()
      ..record(
        MetricEvent(
          type: MetricType.counter,
          name: 'stem_tasks_started_total',
          value: 1,
          tags: const {'queue': 'default'},
        ),
      )
      ..record(
        MetricEvent(
          type: MetricType.histogram,
          name: 'stem_task_duration_seconds',
          value: 250,
          tags: const {'task': 'foo'},
        ),
      )
      ..record(
        MetricEvent(
          type: MetricType.gauge,
          name: 'stem_worker_inflight',
          value: 3,
          tags: const {'worker': 'w1'},
        ),
      );

    final rendered = exporter.render();
    expect(rendered, contains('stem_tasks_started_total'));
    expect(rendered, contains('stem_task_duration_seconds'));
    expect(rendered, contains('stem_worker_inflight'));
  });
}
