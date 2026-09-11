import 'package:contextual/contextual.dart';
import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as dotel;
import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart'
    as api;
import 'package:stem/stem.dart';

/// Bridges Stem's normal logging channel to the OTel log signal without
/// replacing the normal console (or test) channel.
class OTelLogDriver extends LogDriver {
  OTelLogDriver({String name = 'otlp'}) : super(name);

  @override
  Future<void> log(LogEntry entry) async {
    final values = <String, Object>{};
    for (final item in entry.record.context.all().entries) {
      final value = item.value;
      if (value != null) values[item.key] = value;
    }
    dotel.OTel.logger('stem').emit(
      timeStamp: entry.record.time,
      context: dotel.Context.current,
      severityNumber: _severity(entry.record.level),
      severityText: entry.record.level.name,
      body: entry.record.message,
      attributes: api.Attributes.of(values),
    );
  }

  api.Severity _severity(Level level) => switch (level) {
    Level.debug => api.Severity.DEBUG,
    Level.warning => api.Severity.WARN,
    Level.error => api.Severity.ERROR,
    Level.critical || Level.alert || Level.emergency => api.Severity.FATAL,
    _ => api.Severity.INFO,
  };
}

/// The explicit exporters used by the local HTTP/protobuf demonstration.
class LocalTelemetry {
  LocalTelemetry._({
    required this.metricReader,
    required this.spanProcessor,
    required this.stemMetricsExporter,
  });

  final dotel.MetricReader metricReader;
  final dotel.SpanProcessor spanProcessor;
  final DartasticSdkMetricsExporter stemMetricsExporter;

  static Future<LocalTelemetry> start({
    required String endpoint,
    required String serviceName,
  }) async {
    const protocol = dotel.OtlpHttpProtocol.httpProtobuf;
    final spans = dotel.OtlpHttpSpanExporter(
      dotel.OtlpHttpExporterConfig(endpoint: endpoint, protocol: protocol),
    );
    final metrics = dotel.OtlpHttpMetricExporter(
      dotel.OtlpHttpMetricExporterConfig(
        endpoint: endpoint,
        protocol: protocol,
      ),
    );
    final logs = dotel.OtlpHttpLogRecordExporter(
      dotel.OtlpHttpLogRecordExporterConfig(
        endpoint: endpoint,
        protocol: protocol,
      ),
    );
    final processor = dotel.BatchSpanProcessor(spans);
    final reader = dotel.PeriodicExportingMetricReader(
      metrics,
      interval: const Duration(seconds: 5),
    );
    await dotel.OTel.initialize(
      endpoint: endpoint,
      secure: false,
      serviceName: serviceName,
      spanProcessor: processor,
      metricReader: reader,
      metricExporter: metrics,
      logRecordExporter: logs,
      enableMetrics: true,
      enableLogs: true,
    );
    final stemMetricsExporter = DartasticSdkMetricsExporter();
    StemMetrics.instance.addExporter(stemMetricsExporter);
    return LocalTelemetry._(
      metricReader: reader,
      spanProcessor: processor,
      stemMetricsExporter: stemMetricsExporter,
    );
  }

  Future<void> flush() async {
    try {
      await StemMetrics.instance.flush();
      await spanProcessor.forceFlush();
      await metricReader.forceFlush();
      await dotel.OTel.loggerProvider().forceFlush();
    } finally {
      await dotel.OTel.shutdown();
    }
  }
}
