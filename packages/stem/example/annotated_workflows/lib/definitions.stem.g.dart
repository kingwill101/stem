// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: unused_element, unnecessary_lambdas, omit_local_variable_types, unused_import

part of 'definitions.dart';

Map<String, Object?> _stemPayloadMap(Object? value, String typeName) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    final result = <String, Object?>{};
    value.forEach((key, entry) {
      if (key is! String) {
        throw StateError('$typeName payload must use string keys.');
      }
      result[key] = entry;
    });
    return result;
  }
  throw StateError(
    '$typeName payload must decode to Map<String, Object?>, got ${value.runtimeType}.',
  );
}

abstract final class StemPayloadCodecs {
  static final PayloadCodec<WelcomeWorkflowResult> welcomeWorkflowResult =
      PayloadCodec<WelcomeWorkflowResult>(
        encode: (value) => value.toJson(),
        decode: (payload) => WelcomeWorkflowResult.fromJson(
          _stemPayloadMap(payload, "WelcomeWorkflowResult"),
        ),
      );
  static final PayloadCodec<WelcomeRequest> welcomeRequest =
      PayloadCodec<WelcomeRequest>(
        encode: (value) => value.toJson(),
        decode: (payload) =>
            WelcomeRequest.fromJson(_stemPayloadMap(payload, "WelcomeRequest")),
      );
  static final PayloadCodec<WelcomePreparation> welcomePreparation =
      PayloadCodec<WelcomePreparation>(
        encode: (value) => value.toJson(),
        decode: (payload) => WelcomePreparation.fromJson(
          _stemPayloadMap(payload, "WelcomePreparation"),
        ),
      );
  static final PayloadCodec<ContextCaptureResult> contextCaptureResult =
      PayloadCodec<ContextCaptureResult>(
        encode: (value) => value.toJson(),
        decode: (payload) => ContextCaptureResult.fromJson(
          _stemPayloadMap(payload, "ContextCaptureResult"),
        ),
      );
  static final PayloadCodec<EmailDispatch> emailDispatch =
      PayloadCodec<EmailDispatch>(
        encode: (value) => value.toJson(),
        decode: (payload) =>
            EmailDispatch.fromJson(_stemPayloadMap(payload, "EmailDispatch")),
      );
  static final PayloadCodec<EmailDeliveryReceipt> emailDeliveryReceipt =
      PayloadCodec<EmailDeliveryReceipt>(
        encode: (value) => value.toJson(),
        decode: (payload) => EmailDeliveryReceipt.fromJson(
          _stemPayloadMap(payload, "EmailDeliveryReceipt"),
        ),
      );
}

final List<Flow> _stemFlows = <Flow>[
  Flow(
    name: "annotated.flow",
    build: (flow) {
      final impl = AnnotatedFlowWorkflow();
      flow.step<Map<String, Object?>?>(
        "start",
        (ctx) => impl.start(ctx),
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
    WorkflowScriptStepContext context,
    WelcomeRequest request,
  ) {
    return _script.step<ContextCaptureResult>(
      "capture-context",
      (context) => super.captureContext(context, request),
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
      FlowStep.typed<WelcomePreparation>(
        name: "prepare-welcome",
        handler: _stemScriptManifestStepNoop,
        valueCodec: StemPayloadCodecs.welcomePreparation,
        kind: WorkflowStepKind.task,
        taskNames: [],
      ),
      FlowStep(
        name: "normalize-email",
        handler: _stemScriptManifestStepNoop,
        kind: WorkflowStepKind.task,
        taskNames: [],
      ),
      FlowStep(
        name: "build-welcome-subject",
        handler: _stemScriptManifestStepNoop,
        kind: WorkflowStepKind.task,
        taskNames: [],
      ),
      FlowStep(
        name: "deliver-welcome",
        handler: _stemScriptManifestStepNoop,
        kind: WorkflowStepKind.task,
        taskNames: [],
      ),
      FlowStep(
        name: "build-follow-up",
        handler: _stemScriptManifestStepNoop,
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
      FlowStep.typed<ContextCaptureResult>(
        name: "capture-context",
        handler: _stemScriptManifestStepNoop,
        valueCodec: StemPayloadCodecs.contextCaptureResult,
        kind: WorkflowStepKind.task,
        taskNames: [],
      ),
      FlowStep(
        name: "normalize-email",
        handler: _stemScriptManifestStepNoop,
        kind: WorkflowStepKind.task,
        taskNames: [],
      ),
      FlowStep(
        name: "build-welcome-subject",
        handler: _stemScriptManifestStepNoop,
        kind: WorkflowStepKind.task,
        taskNames: [],
      ),
    ],
    resultCodec: StemPayloadCodecs.contextCaptureResult,
    run: (script) => _StemScriptProxy1(script).run(
      script,
      StemPayloadCodecs.welcomeRequest.decode(
        _stemRequireArg(script.params, "request"),
      ),
    ),
  ),
];

abstract final class StemWorkflowDefinitions {
  static final WorkflowRef<Map<String, Object?>, Map<String, Object?>?> flow =
      WorkflowRef<Map<String, Object?>, Map<String, Object?>?>(
        name: "annotated.flow",
        encodeParams: (params) => params,
      );
  static final WorkflowRef<({WelcomeRequest request}), WelcomeWorkflowResult>
  script = WorkflowRef<({WelcomeRequest request}), WelcomeWorkflowResult>(
    name: "annotated.script",
    encodeParams: (params) => <String, Object?>{
      "request": StemPayloadCodecs.welcomeRequest.encode(params.request),
    },
    decodeResult: StemPayloadCodecs.welcomeWorkflowResult.decode,
  );
  static final WorkflowRef<({WelcomeRequest request}), ContextCaptureResult>
  contextScript = WorkflowRef<({WelcomeRequest request}), ContextCaptureResult>(
    name: "annotated.context_script",
    encodeParams: (params) => <String, Object?>{
      "request": StemPayloadCodecs.welcomeRequest.encode(params.request),
    },
    decodeResult: StemPayloadCodecs.contextCaptureResult.decode,
  );
}

Future<Object?> _stemScriptManifestStepNoop(FlowContext context) async => null;

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
  return await Future<Object?>.value(
    sendEmailTyped(
      context,
      StemPayloadCodecs.emailDispatch.decode(_stemRequireArg(args, "dispatch")),
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
  static final TaskDefinition<({EmailDispatch dispatch}), EmailDeliveryReceipt>
  sendEmailTyped =
      TaskDefinition<({EmailDispatch dispatch}), EmailDeliveryReceipt>(
        name: "send_email_typed",
        encodeArgs: (args) => <String, Object?>{
          "dispatch": StemPayloadCodecs.emailDispatch.encode(args.dispatch),
        },
        defaultOptions: const TaskOptions(maxRetries: 1),
        metadata: const TaskMetadata(),
        decodeResult: StemPayloadCodecs.emailDeliveryReceipt.decode,
      );
}

extension StemGeneratedTaskEnqueuer on TaskEnqueuer {
  Future<String> enqueueSendEmail({
    required Map<String, Object?> args,
    Map<String, String> headers = const {},
    TaskOptions? options,
    DateTime? notBefore,
    Map<String, Object?>? meta,
    TaskEnqueueOptions? enqueueOptions,
  }) {
    return enqueueCall(
      StemTaskDefinitions.sendEmail.call(
        args,
        headers: headers,
        options: options,
        notBefore: notBefore,
        meta: meta,
        enqueueOptions: enqueueOptions,
      ),
    );
  }

  Future<String> enqueueSendEmailTyped({
    required EmailDispatch dispatch,
    Map<String, String> headers = const {},
    TaskOptions? options,
    DateTime? notBefore,
    Map<String, Object?>? meta,
    TaskEnqueueOptions? enqueueOptions,
  }) {
    return enqueueCall(
      StemTaskDefinitions.sendEmailTyped.call(
        (dispatch: dispatch),
        headers: headers,
        options: options,
        notBefore: notBefore,
        meta: meta,
        enqueueOptions: enqueueOptions,
      ),
    );
  }
}

extension StemGeneratedTaskResults on Stem {
  Future<TaskResult<Object?>?> waitForSendEmail(
    String taskId, {
    Duration? timeout,
  }) {
    return waitForTaskDefinition(
      taskId,
      StemTaskDefinitions.sendEmail,
      timeout: timeout,
    );
  }

  Future<TaskResult<EmailDeliveryReceipt>?> waitForSendEmailTyped(
    String taskId, {
    Duration? timeout,
  }) {
    return waitForTaskDefinition(
      taskId,
      StemTaskDefinitions.sendEmailTyped,
      timeout: timeout,
    );
  }
}

final List<TaskHandler<Object?>> _stemTasks = <TaskHandler<Object?>>[
  FunctionTaskHandler<Object?>(
    name: "send_email",
    entrypoint: sendEmail,
    options: const TaskOptions(maxRetries: 1),
    metadata: const TaskMetadata(),
  ),
  FunctionTaskHandler<Object?>(
    name: "send_email_typed",
    entrypoint: _stemTaskAdapter0,
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
