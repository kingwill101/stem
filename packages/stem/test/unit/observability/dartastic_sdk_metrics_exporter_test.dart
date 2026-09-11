import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as dotel;
import 'package:stem/stem.dart';
import 'package:test/test.dart';

class _RecordingMetricExporter implements dotel.MetricExporter {
  final List<dotel.MetricData> batches = [];
  int flushes = 0;
  int shutdowns = 0;

  @override
  Future<bool> export(dotel.MetricData data) async {
    batches.add(data);
    return true;
  }

  @override
  Future<bool> forceFlush() async {
    flushes++;
    return true;
  }

  @override
  Future<bool> shutdown() async {
    shutdowns++;
    return true;
  }
}

void main() {
  tearDown(() async {
    await dotel.OTel.reset();
  });

  test('requires an initialized SDK at construction', () async {
    await dotel.OTel.reset();

    expect(
      DartasticSdkMetricsExporter.new,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('requires an initialized Dartastic SDK'),
        ),
      ),
    );
  });

  test('records typed instruments and flushes its owning provider', () async {
    final recording = _RecordingMetricExporter();
    await dotel.OTel.initialize(
      serviceName: 'stem-sdk-metrics-test',
      endpoint: 'http://localhost:4317',
      secure: false,
      metricExporter: recording,
      enableLogs: false,
    );
    final exporter = DartasticSdkMetricsExporter(meterName: 'owned-meter')
      ..record(
        MetricEvent(
          type: MetricType.counter,
          name: 'requests',
          value: 2,
          unit: 'count',
          tags: {'route': '/work'},
        ),
      )
      ..record(
        MetricEvent(
          type: MetricType.histogram,
          name: 'latency',
          value: 1500,
          unit: 'ms',
        ),
      )
      ..record(
        MetricEvent(
          type: MetricType.gauge,
          name: 'queue.depth',
          value: 3,
          unit: 'items',
        ),
      );

    await exporter.flush();
    expect(recording.flushes, greaterThanOrEqualTo(1));
    expect(
      recording.batches.expand((batch) => batch.metrics).map((m) => m.name),
      containsAll(<String>[
        'requests',
        'latency',
        'queue_depth',
      ]),
    );
    final metrics = recording.batches.expand((batch) => batch.metrics).toList();
    expect(metrics.firstWhere((m) => m.name == 'latency').unit, 's');
    expect(metrics.firstWhere((m) => m.name == 'requests').unit, isNull);

    await exporter.shutdown();
    expect(recording.shutdowns, 0);
  });
}
