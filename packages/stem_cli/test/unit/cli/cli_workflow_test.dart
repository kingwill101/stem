import 'dart:convert';

import 'package:stem/stem.dart';
import 'package:stem_cli/src/cli/cli_runner.dart';
import 'package:stem_cli/src/cli/workflow_context.dart';
import 'package:test/test.dart';

void main() {
  group('stem wf', () {
    late InMemoryWorkflowStore store;
    late Flow demoFlow;

    setUp(() {
      store = InMemoryWorkflowStore();
      demoFlow = Flow(
        name: 'demo.workflow',
        build: (flow) {
          flow.step('step-a', (context) async => 'a');
          flow.step('step-b', (context) async => '${context.previousResult}-b');
        },
      );
    });

    Future<WorkflowCliContext> _buildWorkflowContext() async {
      final broker = InMemoryBroker();
      final registry = SimpleTaskRegistry();
      final stem = Stem(broker: broker, registry: registry, backend: null);
      final runtime = WorkflowRuntime(
        stem: stem,
        store: store,
        eventBus: InMemoryEventBus(store),
      );
      registry.register(runtime.workflowRunnerHandler());
      runtime.registerWorkflow(demoFlow.definition);
      return WorkflowCliContext(
        runtime: runtime,
        store: store,
        dispose: () async {
          await runtime.dispose();
          broker.dispose();
        },
      );
    }

    Future<CliContext> _buildCliContext() async {
      final broker = InMemoryBroker();
      return CliContext(
        broker: broker,
        backend: null,
        revokeStore: null,
        routing: RoutingRegistry(RoutingConfig.legacy()),
        dispose: () async {
          broker.dispose();
        },
        registry: SimpleTaskRegistry(),
      );
    }

    test('start registers new workflow run', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runStemCli(
        ['wf', 'start', 'demo.workflow'],
        out: out,
        err: err,
        contextBuilder: _buildCliContext,
        workflowContextBuilder: _buildWorkflowContext,
      );

      expect(code, equals(0), reason: err.toString());
      expect(out.toString(), contains('Started workflow:'));
      final runs = await store.listRuns(limit: 10);
      expect(runs, isNotEmpty);
      expect(runs.first.workflow, 'demo.workflow');
    });

    test('ls --json returns run summaries', () async {
      await runStemCli(
        ['wf', 'start', 'demo.workflow'],
        contextBuilder: _buildCliContext,
        workflowContextBuilder: _buildWorkflowContext,
      );
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runStemCli(
        ['wf', 'ls', '--json'],
        out: out,
        err: err,
        contextBuilder: _buildCliContext,
        workflowContextBuilder: _buildWorkflowContext,
      );
      expect(code, equals(0), reason: err.toString());
      final payload = jsonDecode(out.toString()) as List<dynamic>;
      expect(payload, isNotEmpty);
      expect(
        (payload.first as Map<String, dynamic>)['workflow'],
        'demo.workflow',
      );
    });

    test('show --json displays run details and steps', () async {
      await runStemCli(
        ['wf', 'start', 'demo.workflow'],
        contextBuilder: _buildCliContext,
        workflowContextBuilder: _buildWorkflowContext,
      );
      final run = (await store.listRuns(limit: 1)).first;

      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runStemCli(
        ['wf', 'show', run.id, '--json'],
        out: out,
        err: err,
        contextBuilder: _buildCliContext,
        workflowContextBuilder: _buildWorkflowContext,
      );

      expect(code, equals(0), reason: err.toString());
      final payload = jsonDecode(out.toString()) as Map<String, dynamic>;
      expect(payload['run']['id'], run.id);
      expect(payload['steps'], isList);
    });

    test('cancel transitions run to cancelled', () async {
      await runStemCli(
        ['wf', 'start', 'demo.workflow'],
        contextBuilder: _buildCliContext,
        workflowContextBuilder: _buildWorkflowContext,
      );
      final run = (await store.listRuns(limit: 1)).first;

      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runStemCli(
        ['wf', 'cancel', run.id],
        out: out,
        err: err,
        contextBuilder: _buildCliContext,
        workflowContextBuilder: _buildWorkflowContext,
      );

      expect(code, equals(0), reason: err.toString());
      final cancelled = await store.get(run.id);
      expect(cancelled?.status, WorkflowStatus.cancelled);
    });

    test('rewind clears checkpoints beyond target step', () async {
      // execute workflow once to populate checkpoints
      await runStemCli(
        ['wf', 'start', 'demo.workflow'],
        contextBuilder: _buildCliContext,
        workflowContextBuilder: _buildWorkflowContext,
      );
      final run = (await store.listRuns(limit: 1)).first;

      // Manually save checkpoints to simulate completion
      await store.saveStep(run.id, 'step-a', 'a');
      await store.saveStep(run.id, 'step-b', 'a-b');

      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runStemCli(
        ['wf', 'rewind', run.id, '--step', 'step-b'],
        out: out,
        err: err,
        contextBuilder: _buildCliContext,
        workflowContextBuilder: _buildWorkflowContext,
      );

      expect(code, equals(0), reason: err.toString());
      final steps = await store.listSteps(run.id);
      expect(steps.map((s) => s.name), ['step-a']);
    });
  });
}
