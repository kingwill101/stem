import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('ObservabilityConfig', () {
    setUp(() {
      StemMetrics.instance
        ..reset()
        ..configure();
    });

    test('parseDuration handles supported units', () {
      expect(
        ObservabilityConfig.parseDuration('250ms'),
        equals(const Duration(milliseconds: 250)),
      );
      expect(
        ObservabilityConfig.parseDuration('10s'),
        equals(const Duration(seconds: 10)),
      );
      expect(
        ObservabilityConfig.parseDuration('3m'),
        equals(const Duration(minutes: 3)),
      );
      expect(ObservabilityConfig.parseDuration('invalid'), isNull);
      expect(ObservabilityConfig.parseDuration(null), isNull);
    });

    test('fromEnvironment reads environment variables with trimming', () {
      final config = ObservabilityConfig.fromEnvironment({
        'STEM_HEARTBEAT_INTERVAL': '15s',
        'STEM_WORKER_NAMESPACE': ' prod-east ',
        'STEM_METRIC_EXPORTERS':
            'console, otlp:http://collector:4318/v1/metrics ,prometheus',
        'STEM_OTLP_ENDPOINT': 'http://collector:4318/v1/metrics',
        'STEM_SIGNALS_ENABLED': 'false',
        'STEM_SIGNALS_DISABLED': 'task-prerun, worker-heartbeat',
      });

      expect(config.heartbeatInterval, equals(const Duration(seconds: 15)));
      expect(config.namespace, equals('prod-east'));
      expect(
        config.metricExporters,
        equals([
          'console',
          'otlp:http://collector:4318/v1/metrics',
          'prometheus',
        ]),
      );
      expect(
        config.otlpEndpoint,
        equals(Uri.parse('http://collector:4318/v1/metrics')),
      );
      expect(config.signalConfiguration.enabled, isFalse);
      expect(config.signalConfiguration.enabledSignals['task-prerun'], isFalse);
      expect(
        config.signalConfiguration.enabledSignals['worker-heartbeat'],
        isFalse,
      );
    });

    test('merge prefers non-empty overrides and preserves defaults', () {
      final base = ObservabilityConfig(
        heartbeatInterval: const Duration(seconds: 5),
        namespace: 'base',
        metricExporters: const ['console'],
        otlpEndpoint: Uri.parse('http://base'),
      );
      final override = ObservabilityConfig(
        heartbeatInterval: const Duration(seconds: 20),
        namespace: 'override',
        metricExporters: const [],
      );

      final merged = base.merge(override);

      expect(merged.heartbeatInterval, equals(const Duration(seconds: 20)));
      expect(merged.namespace, equals('override'));
      expect(merged.metricExporters, equals(['console']));
      expect(merged.otlpEndpoint, equals(Uri.parse('http://base')));
    });

    test('applyMetricExporters wires exporters for known specs', () async {
      ObservabilityConfig(
        namespace: 'prod',
        metricExporters: const [
          'prometheus',
          'otlp:http://collector:4318/v1/metrics',
          'otlp', // uses fallback endpoint
        ],
        otlpEndpoint: Uri.parse('http://fallback:4318/v1/metrics'),
      ).applyMetricExporters();

      // Emitting metrics exercises the configured exporters without requiring
      // external systems.
      StemMetrics.instance.increment('stem.test.counter');
      StemMetrics.instance.recordDuration(
        'stem.test.duration',
        const Duration(milliseconds: 250),
      );
      StemMetrics.instance.setGauge('stem.test.gauge', 42);

      final snapshot = StemMetrics.instance.snapshot();
      final counters = snapshot['counters']! as List<dynamic>;
      expect(counters, isNotEmpty);

      await StemMetrics.instance.flush();
    });

    test(
      'applyMetricExporters configures console exporter without emitting',
      () {
        final config = ObservabilityConfig(metricExporters: const ['console']);

        expect(config.applyMetricExporters, returnsNormally);
      },
    );

    test('applySignalConfiguration honors enablement flags', () async {
      addTearDown(() {
        StemSignals.configure(configuration: const StemSignalConfiguration());
      });

      ObservabilityConfig(
        signalConfiguration: const StemSignalConfiguration(enabled: false),
      ).applySignalConfiguration();

      var invoked = false;
      StemSignals.beforeTaskPublish.connect((payload, _) {
        invoked = true;
      });

      final envelope = Envelope(name: 'task', args: const {});
      await StemSignals.beforeTaskPublish.emit(
        BeforeTaskPublishPayload(envelope: envelope, attempt: envelope.attempt),
      );

      expect(invoked, isFalse);
    });
  });
}
