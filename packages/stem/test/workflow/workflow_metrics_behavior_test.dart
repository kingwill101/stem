import 'package:stem/memory.dart';
import 'package:stem/stem.dart';
import 'package:test/test.dart';

class _MetricsRecorder extends MetricsExporter {
  final events = <MetricEvent>[];

  @override
  void record(MetricEvent event) => events.add(event);
}

void main() {
  late InMemoryBroker broker;
  late InMemoryTaskRegistry registry;
  late InMemoryWorkflowStore store;
  late WorkflowRuntime runtime;
  late FakeWorkflowClock clock;
  late _MetricsRecorder metrics;

  setUp(() {
    broker = InMemoryBroker();
    registry = InMemoryTaskRegistry();
    clock = FakeWorkflowClock(DateTime.utc(2024));
    store = InMemoryWorkflowStore(clock: clock);
    metrics = _MetricsRecorder();
    StemMetrics.instance
      ..reset()
      ..configure(exporters: [metrics]);
    runtime = WorkflowRuntime(
      stem: Stem(broker: broker, registry: registry),
      store: store,
      eventBus: InMemoryEventBus(store),
      clock: clock,
    );
    registry.register(runtime.workflowRunnerHandler());
  });

  tearDown(() async {
    await runtime.dispose();
    broker.dispose();
    StemMetrics.instance.reset();
  });

  test(
    'success emits once without duplicate duration after terminal replay',
    () async {
      runtime.registerWorkflow(
        Flow(
          name: 'metrics.success',
          build: (flow) {
            flow
              ..step('first', (context) async => 1)
              ..step('wait', (context) async => 'done');
          },
        ).definition,
      );

      final runId = await store.createRun(
        workflow: 'metrics.success',
        params: {},
      );
      await store.saveStep(runId, 'first', 1);
      await store.suspendUntil(
        runId,
        'first',
        clock.now(),
        data: const {'step': 'first'},
      );
      await store.markResumed(runId, data: const {'step': 'first'});
      await runtime.executeRun(runId);

      expect(_count(metrics, 'stem.workflows.succeeded'), 1);
      expect(_count(metrics, 'stem.workflow.steps.replayed'), 1);
      expect(_count(metrics, 'stem.workflow.step.duration'), 1);
    },
  );

  test(
    'suspension is not failure and resumed step gets one duration',
    () async {
      runtime.registerWorkflow(
        Flow(
          name: 'metrics.suspend',
          build: (flow) => flow.step('wait', (context) async {
            if (context.takeResumeData() == true) return 'done';
            context.sleep(const Duration(seconds: 1));
            return null;
          }),
        ).definition,
      );

      final runId = await runtime.startWorkflow('metrics.suspend');
      await runtime.executeRun(runId);
      expect((await store.get(runId))?.status, WorkflowStatus.suspended);
      expect(_count(metrics, 'stem.workflow.steps.failed'), 0);
      expect(_count(metrics, 'stem.workflows.failed'), 0);
      expect(_count(metrics, 'stem.workflow.step.duration'), 0);

      clock.advance(const Duration(seconds: 1));
      final suspended = await store.get(runId);
      await store.markResumed(runId, data: suspended?.suspensionData);
      await runtime.executeRun(runId);
      expect((await store.get(runId))?.status, WorkflowStatus.completed);
      expect(_count(metrics, 'stem.workflows.succeeded'), 1);
      expect(_count(metrics, 'stem.workflow.step.duration'), 1);
    },
  );

  test('terminal unknown workflow emits failed exactly once', () async {
    final runId = await store.createRun(
      workflow: 'metrics.missing',
      params: {},
    );
    await runtime.executeRun(runId);
    await runtime.executeRun(runId);

    expect((await store.get(runId))?.status, WorkflowStatus.failed);
    expect(_count(metrics, 'stem.workflows.failed'), 1);
    expect(_count(metrics, 'stem.workflow.steps.failed'), 0);
  });
}

int _count(_MetricsRecorder metrics, String name) =>
    metrics.events.where((event) => event.name == name).length;
