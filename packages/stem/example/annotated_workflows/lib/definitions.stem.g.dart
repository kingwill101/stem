// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: unused_element, unnecessary_lambdas, omit_local_variable_types, unused_import

part of 'definitions.dart';

abstract final class StemPayloadCodecs {
  static final PayloadCodec<WelcomeWorkflowResult> welcomeWorkflowResult =
      PayloadCodec<WelcomeWorkflowResult>.json(
        decode: WelcomeWorkflowResult.fromJson,
        typeName: "WelcomeWorkflowResult",
      );
  static final PayloadCodec<WelcomeRequest> welcomeRequest =
      PayloadCodec<WelcomeRequest>.json(
        decode: WelcomeRequest.fromJson,
        typeName: "WelcomeRequest",
      );
  static final PayloadCodec<WelcomePreparation> welcomePreparation =
      PayloadCodec<WelcomePreparation>.json(
        decode: WelcomePreparation.fromJson,
        typeName: "WelcomePreparation",
      );
  static final PayloadCodec<ContextCaptureResult> contextCaptureResult =
      PayloadCodec<ContextCaptureResult>.json(
        decode: ContextCaptureResult.fromJson,
        typeName: "ContextCaptureResult",
      );
  static final PayloadCodec<EmailDispatch> emailDispatch =
      PayloadCodec<EmailDispatch>.json(
        decode: EmailDispatch.fromJson,
        typeName: "EmailDispatch",
      );
  static final PayloadCodec<EmailDeliveryReceipt> emailDeliveryReceipt =
      PayloadCodec<EmailDeliveryReceipt>.json(
        decode: EmailDeliveryReceipt.fromJson,
        typeName: "EmailDeliveryReceipt",
      );
}

final List<Flow> _stemFlows = <Flow>[
  Flow(
    name: "annotated.flow",
    build: (flow) {
      final impl = AnnotatedFlowWorkflow();
      flow.step<Map<String, Object?>?>(
        "start",
        (ctx) => impl.start(context: ctx),
        kind: WorkflowStepKind.task,
        taskNames: [],
      );
    },
  ),
];

class _StemScriptProxy0 extends AnnotatedScriptWorkflow {
  _StemScriptProxy0(this._script);
  final WorkflowScriptContext _script;
  @override
  Future<WelcomePreparation> prepareWelcome(WelcomeRequest request) {
    return _script.step<WelcomePreparation>(
      "prepare-welcome",
      (context) => super.prepareWelcome(request),
    );
  }

  @override
  Future<String> normalizeEmail(String email) {
    return _script.step<String>(
      "normalize-email",
      (context) => super.normalizeEmail(email),
    );
  }

  @override
  Future<String> buildWelcomeSubject(String normalizedEmail) {
    return _script.step<String>(
      "build-welcome-subject",
      (context) => super.buildWelcomeSubject(normalizedEmail),
    );
  }

  @override
  Future<String> deliverWelcome(String normalizedEmail, String subject) {
    return _script.step<String>(
      "deliver-welcome",
      (context) => super.deliverWelcome(normalizedEmail, subject),
    );
  }

  @override
  Future<String> buildFollowUp(String normalizedEmail, String subject) {
    return _script.step<String>(
      "build-follow-up",
      (context) => super.buildFollowUp(normalizedEmail, subject),
    );
  }
}

class _StemScriptProxy1 extends AnnotatedContextScriptWorkflow {
  _StemScriptProxy1(this._script);
  final WorkflowScriptContext _script;
  @override
  Future<ContextCaptureResult> captureContext(
    WelcomeRequest request, {
    WorkflowExecutionContext? context,
  }) {
    return _script.step<ContextCaptureResult>(
      "capture-context",
      (context) => super.captureContext(request, context: context),
    );
  }

  @override
  Future<String> normalizeEmail(String email) {
    return _script.step<String>(
      "normalize-email",
      (context) => super.normalizeEmail(email),
    );
  }

  @override
  Future<String> buildWelcomeSubject(String normalizedEmail) {
    return _script.step<String>(
      "build-welcome-subject",
      (context) => super.buildWelcomeSubject(normalizedEmail),
    );
  }
}

final List<WorkflowScript> _stemScripts = <WorkflowScript>[
  WorkflowScript(
    name: "annotated.script",
    checkpoints: [
      WorkflowCheckpoint.typed<WelcomePreparation>(
        name: "prepare-welcome",
        valueCodec: StemPayloadCodecs.welcomePreparation,
        kind: WorkflowStepKind.task,
        taskNames: [],
      ),
      WorkflowCheckpoint(
        name: "normalize-email",
        kind: WorkflowStepKind.task,
        taskNames: [],
      ),
      WorkflowCheckpoint(
        name: "build-welcome-subject",
        kind: WorkflowStepKind.task,
        taskNames: [],
      ),
      WorkflowCheckpoint(
        name: "deliver-welcome",
        kind: WorkflowStepKind.task,
        taskNames: [],
      ),
      WorkflowCheckpoint(
        name: "build-follow-up",
        kind: WorkflowStepKind.task,
        taskNames: [],
      ),
    ],
    resultCodec: StemPayloadCodecs.welcomeWorkflowResult,
    run: (script) => _StemScriptProxy0(script).run(
      StemPayloadCodecs.welcomeRequest.decode(
        _stemRequireArg(script.params, "request"),
      ),
    ),
  ),
  WorkflowScript(
    name: "annotated.context_script",
    checkpoints: [
      WorkflowCheckpoint.typed<ContextCaptureResult>(
        name: "capture-context",
        valueCodec: StemPayloadCodecs.contextCaptureResult,
        kind: WorkflowStepKind.task,
        taskNames: [],
      ),
      WorkflowCheckpoint(
        name: "normalize-email",
        kind: WorkflowStepKind.task,
        taskNames: [],
      ),
      WorkflowCheckpoint(
        name: "build-welcome-subject",
        kind: WorkflowStepKind.task,
        taskNames: [],
      ),
    ],
    resultCodec: StemPayloadCodecs.contextCaptureResult,
    run: (script) => _StemScriptProxy1(script).run(
      StemPayloadCodecs.welcomeRequest.decode(
        _stemRequireArg(script.params, "request"),
      ),
      context: script,
    ),
  ),
];

abstract final class StemWorkflowDefinitions {
  static final NoArgsWorkflowRef<Map<String, Object?>?> flow =
      NoArgsWorkflowRef<Map<String, Object?>?>(name: "annotated.flow");
  static final WorkflowRef<WelcomeRequest, WelcomeWorkflowResult> script =
      WorkflowRef<WelcomeRequest, WelcomeWorkflowResult>(
        name: "annotated.script",
        encodeParams: (params) => <String, Object?>{
          "request": StemPayloadCodecs.welcomeRequest.encode(params),
        },
        decodeResult: StemPayloadCodecs.welcomeWorkflowResult.decode,
      );
  static final WorkflowRef<WelcomeRequest, ContextCaptureResult> contextScript =
      WorkflowRef<WelcomeRequest, ContextCaptureResult>(
        name: "annotated.context_script",
        encodeParams: (params) => <String, Object?>{
          "request": StemPayloadCodecs.welcomeRequest.encode(params),
        },
        decodeResult: StemPayloadCodecs.contextCaptureResult.decode,
      );
}

Object? _stemRequireArg(Map<String, Object?> args, String name) {
  if (!args.containsKey(name)) {
    throw ArgumentError('Missing required argument "$name".');
  }
  return args[name];
}

Future<Object?> _stemTaskAdapter0(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  return await Future<Object?>.value(sendEmail(args, context: context));
}

Future<Object?> _stemTaskAdapter1(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  return await Future<Object?>.value(
    sendEmailTyped(
      StemPayloadCodecs.emailDispatch.decode(_stemRequireArg(args, "dispatch")),
      context: context,
    ),
  );
}

abstract final class StemTaskDefinitions {
  static final TaskDefinition<Map<String, Object?>, Object?> sendEmail =
      TaskDefinition<Map<String, Object?>, Object?>(
        name: "send_email",
        encodeArgs: (args) => args,
        defaultOptions: const TaskOptions(maxRetries: 1),
        metadata: const TaskMetadata(),
      );
  static final TaskDefinition<EmailDispatch, EmailDeliveryReceipt>
  sendEmailTyped = TaskDefinition<EmailDispatch, EmailDeliveryReceipt>(
    name: "send_email_typed",
    encodeArgs: (args) => <String, Object?>{
      "dispatch": StemPayloadCodecs.emailDispatch.encode(args),
    },
    defaultOptions: const TaskOptions(maxRetries: 1),
    metadata: const TaskMetadata(),
    decodeResult: StemPayloadCodecs.emailDeliveryReceipt.decode,
  );
}

final List<TaskHandler<Object?>> _stemTasks = <TaskHandler<Object?>>[
  FunctionTaskHandler<Object?>(
    name: "send_email",
    entrypoint: _stemTaskAdapter0,
    options: const TaskOptions(maxRetries: 1),
    metadata: const TaskMetadata(),
  ),
  FunctionTaskHandler<Object?>(
    name: "send_email_typed",
    entrypoint: _stemTaskAdapter1,
    options: const TaskOptions(maxRetries: 1),
    metadata: TaskMetadata(
      tags: [],
      idempotent: false,
      attributes: {},
      resultEncoder: CodecTaskPayloadEncoder<EmailDeliveryReceipt>(
        idValue: "stem.generated.send_email_typed.result",
        codec: StemPayloadCodecs.emailDeliveryReceipt,
      ),
    ),
  ),
];

final List<WorkflowManifestEntry> _stemWorkflowManifest =
    <WorkflowManifestEntry>[
      ..._stemFlows.map((flow) => flow.definition.toManifestEntry()),
      ..._stemScripts.map((script) => script.definition.toManifestEntry()),
    ];

final StemModule stemModule = StemModule(
  flows: _stemFlows,
  scripts: _stemScripts,
  tasks: _stemTasks,
  workflowManifest: _stemWorkflowManifest,
);
