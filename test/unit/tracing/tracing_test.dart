import 'dart:async';

import 'package:opentelemetry/api.dart' as otel;
import 'package:opentelemetry/sdk.dart'
    show SimpleSpanProcessor, SpanExporter, TracerProviderBase, ReadOnlySpan;
import 'package:stem/stem.dart';
import 'package:test/test.dart';

class _RecordingSpanExporter implements SpanExporter {
  final List<ReadOnlySpan> spans = [];

  @override
  void export(List<ReadOnlySpan> spans) {
    this.spans.addAll(spans);
  }

  @override
  void forceFlush() {}

  @override
  void shutdown() {}
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

  setUpAll(() {
    try {
      final provider = TracerProviderBase(
        processors: [SimpleSpanProcessor(exporter)],
      );
      otel.registerGlobalTracerProvider(provider);
    } on StateError {
      // Global provider already registered; assume spans will still be captured.
    }
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

    // Debug: collect spans for analysis.
    // ignore: avoid_print
    final spanNames = exporter.spans.map((span) => span.name).toList();
    expect(spanNames, contains('stem.enqueue'));
    expect(spanNames, contains('stem.consume'));
    expect(
      spanNames.any((name) => name.startsWith('stem.execute.trace.test')),
      isTrue,
    );

    final traceIds = exporter.spans
        .map((span) => span.spanContext.traceId.toString())
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

    expect(
      consumeSpan.parentSpanId.toString(),
      enqueueSpan.spanContext.spanId.toString(),
    );
    expect(
      executeSpan.parentSpanId.toString(),
      consumeSpan.spanContext.spanId.toString(),
    );
  });
}
