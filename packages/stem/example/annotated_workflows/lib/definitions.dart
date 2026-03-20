import 'package:stem/stem.dart';

part 'definitions.stem.g.dart';

class WelcomeRequest {
  const WelcomeRequest({required this.email});

  final String email;

  Map<String, Object?> toJson() => {'email': email};

  factory WelcomeRequest.fromJson(Map<String, Object?> json) {
    return WelcomeRequest(email: json['email'] as String);
  }
}

class EmailDispatch {
  const EmailDispatch({
    required this.email,
    required this.subject,
    required this.body,
    required this.tags,
  });

  final String email;
  final String subject;
  final String body;
  final List<String> tags;

  Map<String, Object?> toJson() => {
    'email': email,
    'subject': subject,
    'body': body,
    'tags': tags,
  };

  factory EmailDispatch.fromJson(Map<String, Object?> json) {
    return EmailDispatch(
      email: json['email'] as String,
      subject: json['subject'] as String,
      body: json['body'] as String,
      tags: (json['tags'] as List<Object?>).cast<String>(),
    );
  }
}

class EmailDeliveryReceipt {
  const EmailDeliveryReceipt({
    required this.taskId,
    required this.attempt,
    required this.email,
    required this.subject,
    required this.tags,
    required this.meta,
  });

  final String taskId;
  final int attempt;
  final String email;
  final String subject;
  final List<String> tags;
  final Map<String, Object?> meta;

  Map<String, Object?> toJson() => {
    'taskId': taskId,
    'attempt': attempt,
    'email': email,
    'subject': subject,
    'tags': tags,
    'meta': meta,
  };

  factory EmailDeliveryReceipt.fromJson(Map<String, Object?> json) {
    return EmailDeliveryReceipt(
      taskId: json['taskId'] as String,
      attempt: json['attempt'] as int,
      email: json['email'] as String,
      subject: json['subject'] as String,
      tags: (json['tags'] as List<Object?>).cast<String>(),
      meta: Map<String, Object?>.from(json['meta'] as Map),
    );
  }
}

class WelcomePreparation {
  const WelcomePreparation({
    required this.normalizedEmail,
    required this.subject,
  });

  final String normalizedEmail;
  final String subject;

  Map<String, Object?> toJson() => {
    'normalizedEmail': normalizedEmail,
    'subject': subject,
  };

  factory WelcomePreparation.fromJson(Map<String, Object?> json) {
    return WelcomePreparation(
      normalizedEmail: json['normalizedEmail'] as String,
      subject: json['subject'] as String,
    );
  }
}

class WelcomeWorkflowResult {
  const WelcomeWorkflowResult({
    required this.normalizedEmail,
    required this.subject,
    required this.followUp,
  });

  final String normalizedEmail;
  final String subject;
  final String followUp;

  Map<String, Object?> toJson() => {
    'normalizedEmail': normalizedEmail,
    'subject': subject,
    'followUp': followUp,
  };

  factory WelcomeWorkflowResult.fromJson(Map<String, Object?> json) {
    return WelcomeWorkflowResult(
      normalizedEmail: json['normalizedEmail'] as String,
      subject: json['subject'] as String,
      followUp: json['followUp'] as String,
    );
  }
}

class ContextCaptureResult {
  const ContextCaptureResult({
    required this.workflow,
    required this.runId,
    required this.stepName,
    required this.stepIndex,
    required this.iteration,
    required this.idempotencyKey,
    required this.normalizedEmail,
    required this.subject,
    required this.childRunId,
    required this.childResult,
  });

  final String workflow;
  final String runId;
  final String stepName;
  final int stepIndex;
  final int iteration;
  final String idempotencyKey;
  final String normalizedEmail;
  final String subject;
  final String childRunId;
  final WelcomeWorkflowResult childResult;

  Map<String, Object?> toJson() => {
    'workflow': workflow,
    'runId': runId,
    'stepName': stepName,
    'stepIndex': stepIndex,
    'iteration': iteration,
    'idempotencyKey': idempotencyKey,
    'normalizedEmail': normalizedEmail,
    'subject': subject,
    'childRunId': childRunId,
    'childResult': childResult.toJson(),
  };

  factory ContextCaptureResult.fromJson(Map<String, Object?> json) {
    return ContextCaptureResult(
      workflow: json['workflow'] as String,
      runId: json['runId'] as String,
      stepName: json['stepName'] as String,
      stepIndex: json['stepIndex'] as int,
      iteration: json['iteration'] as int,
      idempotencyKey: json['idempotencyKey'] as String,
      normalizedEmail: json['normalizedEmail'] as String,
      subject: json['subject'] as String,
      childRunId: json['childRunId'] as String,
      childResult: WelcomeWorkflowResult.fromJson(
        Map<String, Object?>.from(json['childResult'] as Map),
      ),
    );
  }
}

@WorkflowDefn(name: 'annotated.flow')
class AnnotatedFlowWorkflow {
  @WorkflowStep()
  Future<Map<String, Object?>?> start({FlowContext? context}) async {
    final ctx = context!;
    if (!ctx.sleepUntilResumed(const Duration(milliseconds: 50))) {
      return null;
    }
    final childResult = await ctx
        .startWorkflowBuilder(
          definition: StemWorkflowDefinitions.script,
          params: const WelcomeRequest(email: 'flow-child@example.com'),
        )
        .startAndWait(timeout: const Duration(seconds: 2));
    return {
      'workflow': ctx.workflow,
      'runId': ctx.runId,
      'stepName': ctx.stepName,
      'stepIndex': ctx.stepIndex,
      'iteration': ctx.iteration,
      'idempotencyKey': ctx.idempotencyKey(),
      'childRunId': childResult?.runId,
      'childResult': childResult?.value?.toJson(),
    };
  }
}

@WorkflowDefn(name: 'annotated.script', kind: WorkflowKind.script)
class AnnotatedScriptWorkflow {
  Future<WelcomeWorkflowResult> run(WelcomeRequest request) async {
    final prepared = await prepareWelcome(request);
    final normalizedEmail = prepared.normalizedEmail;
    final subject = prepared.subject;
    final followUp = await deliverWelcome(normalizedEmail, subject);
    return WelcomeWorkflowResult(
      normalizedEmail: normalizedEmail,
      subject: subject,
      followUp: followUp,
    );
  }

  @WorkflowStep(name: 'prepare-welcome')
  Future<WelcomePreparation> prepareWelcome(WelcomeRequest request) async {
    final normalizedEmail = await normalizeEmail(request.email);
    final subject = await buildWelcomeSubject(normalizedEmail);
    return WelcomePreparation(
      normalizedEmail: normalizedEmail,
      subject: subject,
    );
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
  Future<ContextCaptureResult> run(
    WelcomeRequest request, {
    WorkflowScriptContext? context,
  }) async {
    return captureContext(request);
  }

  @WorkflowStep(name: 'capture-context')
  Future<ContextCaptureResult> captureContext(
    WelcomeRequest request, {
    WorkflowScriptStepContext? context,
  }) async {
    final ctx = context!;
    final normalizedEmail = await normalizeEmail(request.email);
    final subject = await buildWelcomeSubject(normalizedEmail);
    final childResult = await ctx
        .startWorkflowBuilder(
          definition: StemWorkflowDefinitions.script,
          params: WelcomeRequest(email: normalizedEmail),
        )
        .startAndWait(timeout: const Duration(seconds: 2));
    return ContextCaptureResult(
      workflow: ctx.workflow,
      runId: ctx.runId,
      stepName: ctx.stepName,
      stepIndex: ctx.stepIndex,
      iteration: ctx.iteration,
      idempotencyKey: ctx.idempotencyKey('welcome'),
      normalizedEmail: normalizedEmail,
      subject: subject,
      childRunId: childResult!.runId,
      childResult: childResult.value!,
    );
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
  Map<String, Object?> args, {
  TaskInvocationContext? context,
}) async {
  final ctx = context!;
  ctx.heartbeat();
  // No-op task for example purposes.
}

@TaskDefn(name: 'send_email_typed', options: TaskOptions(maxRetries: 1))
Future<EmailDeliveryReceipt> sendEmailTyped(
  EmailDispatch dispatch, {
  TaskInvocationContext? context,
}) async {
  final ctx = context!;
  ctx.heartbeat();
  await ctx.progress(
    100,
    data: {'email': dispatch.email, 'tagCount': dispatch.tags.length},
  );
  return EmailDeliveryReceipt(
    taskId: ctx.id,
    attempt: ctx.attempt,
    email: dispatch.email,
    subject: dispatch.subject,
    tags: dispatch.tags,
    meta: ctx.meta,
  );
}
