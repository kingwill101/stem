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

  tearDown(StemMetrics.instance.reset);

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
    final taskId = await stem.enqueue(
      'trace.test',
      meta: const {
        'stem.namespace': 'billing',
        'stem.workflow.runId': 'wf-run-123',
        'stem.workflow.name': 'invoice_pipeline',
        'stem.workflow.step': 'charge',
        'stem.workflow.stepId': 'charge#2',
        'stem.workflow.stepIndex': 2,
        'stem.workflow.iteration': 4,
        'stem.workflow.stepAttempt': 1,
        'stem.parentTaskId': 'parent-1',
        'stem.rootTaskId': 'root-1',
      },
    );

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

    expect(
      parentSpanId(consumeSpan),
      anyOf(enqueueSpan.spanContext.spanId.hexString, isNull),
    );
    final allowedExecuteParents = {
      consumeSpan.spanContext.spanId.hexString,
      enqueueSpan.spanContext.spanId.hexString,
      null,
    };
    expect(allowedExecuteParents, contains(parentSpanId(executeSpan)));

    expect(enqueueSpan.attributes.getString('stem.task.id'), taskId);
    expect(enqueueSpan.attributes.getString('stem.task'), 'trace.test');
    expect(enqueueSpan.attributes.getString('stem.queue'), 'default');
    expect(enqueueSpan.attributes.getInt('stem.task.attempt'), 0);
    final maxRetries = enqueueSpan.attributes.getInt('stem.task.max_retries');
    expect(maxRetries, isNotNull);
    expect(enqueueSpan.attributes.getString('stem.namespace'), 'billing');
    expect(
      enqueueSpan.attributes.getString('stem.workflow.run_id'),
      'wf-run-123',
    );
    expect(
      enqueueSpan.attributes.getString('stem.workflow.name'),
      'invoice_pipeline',
    );
    expect(enqueueSpan.attributes.getString('stem.workflow.step'), 'charge');
    expect(
      enqueueSpan.attributes.getString('stem.workflow.step_id'),
      'charge#2',
    );
    expect(enqueueSpan.attributes.getInt('stem.workflow.step_index'), 2);
    expect(enqueueSpan.attributes.getInt('stem.workflow.iteration'), 4);
    expect(enqueueSpan.attributes.getInt('stem.workflow.step_attempt'), 1);
    expect(enqueueSpan.attributes.getString('stem.parent_task_id'), 'parent-1');
    expect(enqueueSpan.attributes.getString('stem.root_task_id'), 'root-1');

    expect(consumeSpan.attributes.getString('stem.task.id'), taskId);
    expect(consumeSpan.attributes.getInt('stem.task.max_retries'), maxRetries);
    expect(consumeSpan.attributes.getString('stem.worker.id'), 'trace-worker');
    expect(consumeSpan.attributes.getString('stem.span.phase'), 'consume');
    expect(consumeSpan.attributes.getString('stem.namespace'), 'billing');
    expect(
      consumeSpan.attributes.getString('stem.workflow.run_id'),
      'wf-run-123',
    );
    expect(
      consumeSpan.attributes.getString('stem.workflow.step_id'),
      'charge#2',
    );

    expect(executeSpan.attributes.getString('stem.task.id'), taskId);
    expect(executeSpan.attributes.getInt('stem.task.max_retries'), maxRetries);
    expect(executeSpan.attributes.getString('stem.worker.id'), 'trace-worker');
    expect(executeSpan.attributes.getString('stem.span.phase'), 'execute');
    expect(executeSpan.attributes.getString('stem.namespace'), 'billing');
    expect(
      executeSpan.attributes.getString('stem.workflow.run_id'),
      'wf-run-123',
    );
    expect(
      executeSpan.attributes.getString('stem.workflow.step_id'),
      'charge#2',
    );
  });

  test('consume starts a new trace when trace headers are missing', () async {
    final broker = InMemoryBroker();
    final backend = InMemoryResultBackend();
    final registry = SimpleTaskRegistry()
      ..register(
        FunctionTaskHandler<void>(
          name: 'trace.test',
          entrypoint: (context, args) async {
            await Future<void>.delayed(const Duration(milliseconds: 5));
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
      concurrency: 1,
    );
    await worker.start();

    final first = Envelope(name: 'trace.test', args: const {});
    final second = Envelope(name: 'trace.test', args: const {});
    await broker.publish(first);
    await broker.publish(second);

    await _waitFor(() async {
      final firstStatus = await backend.get(first.id);
      final secondStatus = await backend.get(second.id);
      return firstStatus?.state == TaskState.succeeded &&
          secondStatus?.state == TaskState.succeeded;
    });

    await worker.shutdown();
    broker.dispose();

    final consumeSpans = exporter.spans
        .where((span) => span.name == 'stem.consume')
        .toList(growable: false);
    expect(consumeSpans.length, greaterThanOrEqualTo(2));

    String? parentSpanId(dotel.Span span) {
      return span.parentSpanContext?.spanId.hexString ??
          span.parentSpan?.spanContext.spanId.hexString;
    }

    expect(parentSpanId(consumeSpans[0]), isNull);
    expect(parentSpanId(consumeSpans[1]), isNull);

    final consumeTraceIds = consumeSpans
        .take(2)
        .map((span) => span.spanContext.traceId.hexString)
        .toSet();
    expect(consumeTraceIds.length, equals(2));
  });
}
