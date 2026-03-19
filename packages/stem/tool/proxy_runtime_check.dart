import 'dart:io';

import 'package:stem/stem.dart';

class ScriptDef {
  Future<String> run(WorkflowScriptContext script) async {
    return sendEmail('user@example.com');
  }

  Future<String> sendEmail(String email) async {
    return email;
  }
}

class ScriptProxy extends ScriptDef {
  ScriptProxy(this._script);
  final WorkflowScriptContext _script;

  @override
  Future<String> sendEmail(String email) {
    return _script.step<String>(
      'send-email',
      (context) => super.sendEmail(email),
    );
  }
}

Future<void> main() async {
  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();
  final registry = InMemoryTaskRegistry();
  final stem = Stem(broker: broker, registry: registry, backend: backend);
  final store = InMemoryWorkflowStore();
  final runtime = WorkflowRuntime(
    stem: stem,
    store: store,
    eventBus: InMemoryEventBus(store),
    continuationQueue: 'workflow-continue',
  );

  registry.register(runtime.workflowRunnerHandler());
  runtime.registerWorkflow(
    WorkflowScript(
      name: 'proxy.script',
      run: (script) => ScriptProxy(script).run(script),
    ).definition,
  );

  final runId = await runtime.startWorkflow('proxy.script');
  await runtime.executeRun(runId);
  final detail = await runtime.viewRunDetail(runId);
  stdout.writeln(
    'result=${detail?.run.result} checkpoints=${detail?.steps.length}',
  );
  if ((detail?.steps.length ?? 0) > 0) {
    stdout.writeln('checkpointName=${detail!.steps.first.stepName}');
  }

  await runtime.dispose();
  await backend.close();
  broker.dispose();
}
