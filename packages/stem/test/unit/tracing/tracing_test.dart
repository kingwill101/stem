import 'dart:async';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as dotel;
import 'package:stem/stem.dart';
import 'package:test/test.dart';

class _RecordingSpanExporter implements dotel.SpanExporter {
  final List<dotel.Span> spans = [];

  @override
  Future<void> export(List<dotel.Span> spans) async {
    this.spans.addAll(spans);
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
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

void main() {
  final exporter = _RecordingSpanExporter();

  setUpAll(() async {
    await dotel.OTel.reset();
    await dotel.OTel.initialize(
      serviceName: 'stem-tracing-test',
      endpoint: 'http://localhost:4317',
      secure: false,
      spanProcessor: dotel.SimpleSpanProcessor(exporter),
      enableMetrics: false,
    );
  });

  tearDownAll(() async {
    await dotel.OTel.shutdown();
  });

  setUp(() {
    exporter.spans.clear();
    StemMetrics.instance.reset();
  });

  tearDown(() {
    StemMetrics.instance.reset();
  });

  test('traces flow from enqueue to execution', () async {
    final broker = InMemoryBroker();
    final backend = InMemoryResultBackend();
    final registry = SimpleTaskRegistry()
      ..register(
        FunctionTaskHandler<void>(
          name: 'trace.test',
          entrypoint: (context, args) async {
            await context.extendLease(const Duration(milliseconds: 5));
            args.isEmpty;
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return;
          },
        ),
      );

    final worker = Worker(
      broker: broker,
      registry: registry,
      backend: backend,
      consumerName: 'trace-worker',
      heartbeatTransport: const NoopHeartbeatTransport(),
    );
    await worker.start();

    final stem = Stem(broker: broker, registry: registry, backend: backend);
    final taskId = await stem.enqueue('trace.test');

    await _waitFor(() async {
      final status = await backend.get(taskId);
      return status?.state == TaskState.succeeded;
    });

    await worker.shutdown();
    broker.dispose();

    final spanNames = exporter.spans.map((span) => span.name).toList();
    expect(spanNames, contains('stem.enqueue'));
    expect(spanNames, contains('stem.consume'));
    expect(
      spanNames.any((name) => name.startsWith('stem.execute.trace.test')),
      isTrue,
    );

    final traceIds = exporter.spans
        .map((span) => span.spanContext.traceId.hexString)
        .toSet();
    expect(traceIds.length, equals(1));

    final enqueueSpan = exporter.spans.firstWhere(
      (span) => span.name == 'stem.enqueue',
    );
    final consumeSpan = exporter.spans.firstWhere(
      (span) => span.name == 'stem.consume',
    );
    final executeSpan = exporter.spans.firstWhere(
      (span) => span.name.startsWith('stem.execute.'),
    );

    String? parentSpanId(dotel.Span span) {
      return span.parentSpanContext?.spanId.hexString ??
          span.parentSpan?.spanContext.spanId.hexString;
    }

    expect(parentSpanId(consumeSpan), enqueueSpan.spanContext.spanId.hexString);
    final allowedExecuteParents = {
      consumeSpan.spanContext.spanId.hexString,
      enqueueSpan.spanContext.spanId.hexString,
    };
    expect(allowedExecuteParents, contains(parentSpanId(executeSpan)));
  });
}
