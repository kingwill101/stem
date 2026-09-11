import 'dart:async';

import 'package:contextual/contextual.dart' show Context, Level;
import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as otel;
import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart'
    as api;
import 'package:stem/src/observability/logging.dart' as logging;
import 'package:stem/stem.dart';
import 'package:test/test.dart';

import '../../../example/observability/telemetry_helpers.dart';

void main() {
  test(
    'Stem log driver preserves native execution context and filtering',
    () async {
      final logs = _Logs();
      final spans = _Spans();
      await otel.OTel.reset();
      await otel.OTel.initialize(
        serviceName: 'local-telemetry-test',
        spanProcessor: otel.SimpleSpanProcessor(spans),
        logRecordProcessor: otel.SimpleLogRecordProcessor(logs),
        enableMetrics: false,
      );
      addTearDown(otel.OTel.shutdown);
      final logger = logging.createStemLogger()
        ..addChannel('otlp', OTelLogDriver());
      String? traceId;
      String? spanId;
      await StemTracer.instance.trace<void>('test.operation', () async {
        final fields = StemTracer.instance.traceFields();
        traceId = fields['traceId'];
        spanId = fields['spanId'];
        logger
          ..debug('filtered debug')
          ..info('inside operation', Context({'phase': 'execute'}))
          ..critical('critical condition');
        await logs.received.future.timeout(const Duration(seconds: 2));
      });
      await otel.OTel.loggerProvider().forceFlush();

      expect(logs.records, hasLength(2));
      final log = logs.records.first;
      expect(log.body, 'inside operation');
      expect(log.traceId?.hexString, traceId);
      expect(log.spanId?.hexString, spanId);
      expect(log.severityText, Level.info.name);
      expect(logs.records.last.severityNumber, api.Severity.FATAL);
      expect(spans.values.single.spanContext.spanId.hexString, spanId);
      expect(traceId, isNotNull);
      expect(spanId, isNotNull);
    },
  );
}

class _Logs implements otel.LogRecordExporter {
  final records = <otel.ReadableLogRecord>[];
  final received = Completer<void>();

  @override
  Future<otel.ExportResult> export(List<otel.ReadableLogRecord> batch) async {
    records.addAll(batch);
    if (records.length >= 2 && !received.isCompleted) received.complete();
    return otel.ExportResult.success;
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}

class _Spans implements otel.SpanExporter {
  final values = <otel.Span>[];

  @override
  Future<void> export(List<otel.Span> spans) async => values.addAll(spans);

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}
