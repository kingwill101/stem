import 'package:stem/stem.dart';

part 'definitions.stem.g.dart';

@WorkflowDefn(name: 'annotated.flow')
class AnnotatedFlowWorkflow {
  @WorkflowStep()
  Future<Map<String, Object?>?> start(FlowContext ctx) async {
    final resume = ctx.takeResumeData();
    if (resume == null) {
      ctx.sleep(const Duration(milliseconds: 50));
      return null;
    }
    return {
      'workflow': ctx.workflow,
      'runId': ctx.runId,
      'stepName': ctx.stepName,
      'stepIndex': ctx.stepIndex,
      'iteration': ctx.iteration,
      'idempotencyKey': ctx.idempotencyKey(),
    };
  }
}

@WorkflowDefn(name: 'annotated.script', kind: WorkflowKind.script)
class AnnotatedScriptWorkflow {
  Future<Map<String, Object?>> run(String email) async {
    final prepared = await prepareWelcome(email);
    final normalizedEmail = prepared['normalizedEmail'] as String;
    final subject = prepared['subject'] as String;
    final followUp = await deliverWelcome(normalizedEmail, subject);
    return {
      'normalizedEmail': normalizedEmail,
      'subject': subject,
      'followUp': followUp,
    };
  }

  @WorkflowStep(name: 'prepare-welcome')
  Future<Map<String, Object?>> prepareWelcome(String email) async {
    final normalizedEmail = await normalizeEmail(email);
    final subject = await buildWelcomeSubject(normalizedEmail);
    return {'normalizedEmail': normalizedEmail, 'subject': subject};
  }

  @WorkflowStep(name: 'normalize-email')
  Future<String> normalizeEmail(String email) async {
    return email.trim().toLowerCase();
  }

  @WorkflowStep(name: 'build-welcome-subject')
  Future<String> buildWelcomeSubject(String normalizedEmail) async {
    return 'welcome:$normalizedEmail';
  }

  @WorkflowStep(name: 'deliver-welcome')
  Future<String> deliverWelcome(String normalizedEmail, String subject) async {
    return buildFollowUp(normalizedEmail, subject);
  }

  @WorkflowStep(name: 'build-follow-up')
  Future<String> buildFollowUp(String normalizedEmail, String subject) async {
    return '$subject|follow-up:$normalizedEmail';
  }
}

@WorkflowDefn(name: 'annotated.context_script', kind: WorkflowKind.script)
class AnnotatedContextScriptWorkflow {
  @WorkflowRun()
  Future<Map<String, Object?>> run(
    WorkflowScriptContext script,
    String email,
  ) async {
    return script.step<Map<String, Object?>>(
      'enter-context-step',
      (ctx) => captureContext(ctx, email),
    );
  }

  @WorkflowStep(name: 'capture-context')
  Future<Map<String, Object?>> captureContext(
    WorkflowScriptStepContext ctx,
    String email,
  ) async {
    final normalizedEmail = await normalizeEmail(email);
    final subject = await buildWelcomeSubject(normalizedEmail);
    return {
      'workflow': ctx.workflow,
      'runId': ctx.runId,
      'stepName': ctx.stepName,
      'stepIndex': ctx.stepIndex,
      'iteration': ctx.iteration,
      'idempotencyKey': ctx.idempotencyKey('welcome'),
      'normalizedEmail': normalizedEmail,
      'subject': subject,
    };
  }

  @WorkflowStep(name: 'normalize-email')
  Future<String> normalizeEmail(String email) async {
    return email.trim().toLowerCase();
  }

  @WorkflowStep(name: 'build-welcome-subject')
  Future<String> buildWelcomeSubject(String normalizedEmail) async {
    return 'welcome:$normalizedEmail';
  }
}

@TaskDefn(name: 'send_email', options: TaskOptions(maxRetries: 1))
Future<void> sendEmail(
  TaskInvocationContext ctx,
  Map<String, Object?> args,
) async {
  // No-op task for example purposes.
}

@TaskDefn(name: 'send_email_typed', options: TaskOptions(maxRetries: 1))
Future<Map<String, Object?>> sendEmailTyped(
  TaskInvocationContext ctx,
  String email,
  Map<String, Object?> message,
  List<Object?> tags,
) async {
  ctx.heartbeat();
  await ctx.progress(100, data: {'email': email, 'tagCount': tags.length});
  return {
    'taskId': ctx.id,
    'attempt': ctx.attempt,
    'email': email,
    'subject': message['subject'],
    'tags': tags,
    'meta': ctx.meta,
  };
}
