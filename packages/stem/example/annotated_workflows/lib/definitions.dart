import 'package:stem/stem.dart';

@WorkflowDefn(name: 'annotated.flow')
class AnnotatedFlowWorkflow {
  @workflow.step
  Future<String?> start(FlowContext ctx) async {
    final resume = ctx.takeResumeData();
    if (resume == null) {
      ctx.sleep(const Duration(milliseconds: 50));
      return null;
    }
    return 'flow-complete';
  }
}

@WorkflowDefn(name: 'annotated.script', kind: WorkflowKind.script)
class AnnotatedScriptWorkflow {
  @WorkflowRun()
  Future<String> run(WorkflowScriptContext script) async {
    await script.step<void>('sleep', (ctx) async {
      final resume = ctx.takeResumeData();
      if (resume == null) {
        await ctx.sleep(const Duration(milliseconds: 50));
      }
    });
    return 'script-complete';
  }
}

@TaskDefn(name: 'send_email', options: TaskOptions(maxRetries: 1))
Future<void> sendEmail(
  TaskInvocationContext ctx,
  Map<String, Object?> args,
) async {
  // No-op task for example purposes.
}
