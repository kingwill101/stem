// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: unused_element, unnecessary_lambdas, omit_local_variable_types, unused_import

part of 'definitions.dart';

final List<Flow> stemFlows = <Flow>[
  Flow(
    name: "annotated.flow",
    build: (flow) {
      final impl = AnnotatedFlowWorkflow();
      flow.step(
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
  Future<Map<String, Object?>> prepareWelcome(String email) {
    return _script.step<Map<String, Object?>>(
      "prepare-welcome",
      (context) => super.prepareWelcome(email),
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
  Future<Map<String, Object?>> captureContext(
    WorkflowScriptStepContext context,
    String email,
  ) {
    return _script.step<Map<String, Object?>>(
      "capture-context",
      (context) => super.captureContext(context, email),
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

final List<WorkflowScript> stemScripts = <WorkflowScript>[
  WorkflowScript(
    name: "annotated.script",
    checkpoints: [
      FlowStep(
        name: "prepare-welcome",
        handler: _stemScriptManifestStepNoop,
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
    run: (script) => _StemScriptProxy0(
      script,
    ).run((_stemRequireArg(script.params, "email") as String)),
  ),
  WorkflowScript(
    name: "annotated.context_script",
    checkpoints: [
      FlowStep(
        name: "capture-context",
        handler: _stemScriptManifestStepNoop,
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
    run: (script) => _StemScriptProxy1(
      script,
    ).run(script, (_stemRequireArg(script.params, "email") as String)),
  ),
];

abstract final class StemWorkflowNames {
  static const String flow = "annotated.flow";
  static const String script = "annotated.script";
  static const String contextScript = "annotated.context_script";
}

extension StemGeneratedWorkflowAppStarters on StemWorkflowApp {
  Future<String> startFlow({
    Map<String, Object?> params = const {},
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    return startWorkflow(
      StemWorkflowNames.flow,
      params: params,
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    );
  }

  Future<String> startScript({
    required String email,
    Map<String, Object?> extraParams = const {},
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    final params = <String, Object?>{...extraParams, "email": email};
    return startWorkflow(
      StemWorkflowNames.script,
      params: params,
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    );
  }

  Future<String> startContextScript({
    required String email,
    Map<String, Object?> extraParams = const {},
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    final params = <String, Object?>{...extraParams, "email": email};
    return startWorkflow(
      StemWorkflowNames.contextScript,
      params: params,
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    );
  }
}

extension StemGeneratedWorkflowRuntimeStarters on WorkflowRuntime {
  Future<String> startFlow({
    Map<String, Object?> params = const {},
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    return startWorkflow(
      StemWorkflowNames.flow,
      params: params,
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    );
  }

  Future<String> startScript({
    required String email,
    Map<String, Object?> extraParams = const {},
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    final params = <String, Object?>{...extraParams, "email": email};
    return startWorkflow(
      StemWorkflowNames.script,
      params: params,
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    );
  }

  Future<String> startContextScript({
    required String email,
    Map<String, Object?> extraParams = const {},
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    final params = <String, Object?>{...extraParams, "email": email};
    return startWorkflow(
      StemWorkflowNames.contextScript,
      params: params,
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    );
  }
}

final List<WorkflowManifestEntry> stemWorkflowManifest =
    <WorkflowManifestEntry>[
      ...stemFlows.map((flow) => flow.definition.toManifestEntry()),
      ...stemScripts.map((script) => script.definition.toManifestEntry()),
    ];

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
      (_stemRequireArg(args, "email") as String),
      (_stemRequireArg(args, "message") as Map<String, Object?>),
      (_stemRequireArg(args, "tags") as List<Object?>),
    ),
  );
}

final List<TaskHandler<Object?>> stemTasks = <TaskHandler<Object?>>[
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
    metadata: const TaskMetadata(),
  ),
];

void registerStemDefinitions({
  required WorkflowRegistry workflows,
  required TaskRegistry tasks,
}) {
  for (final flow in stemFlows) {
    workflows.register(flow.definition);
  }
  for (final script in stemScripts) {
    workflows.register(script.definition);
  }
  for (final handler in stemTasks) {
    tasks.register(handler);
  }
}

Future<StemWorkflowApp> createStemGeneratedWorkflowApp({
  required StemApp stemApp,
  bool registerTasks = true,
  Duration pollInterval = const Duration(milliseconds: 500),
  Duration leaseExtension = const Duration(seconds: 30),
  WorkflowRegistry? workflowRegistry,
  WorkflowIntrospectionSink? introspectionSink,
}) async {
  if (registerTasks) {
    for (final handler in stemTasks) {
      stemApp.register(handler);
    }
  }
  return StemWorkflowApp.create(
    stemApp: stemApp,
    flows: stemFlows,
    scripts: stemScripts,
    pollInterval: pollInterval,
    leaseExtension: leaseExtension,
    workflowRegistry: workflowRegistry,
    introspectionSink: introspectionSink,
  );
}

Future<StemWorkflowApp> createStemGeneratedInMemoryApp() async {
  final stemApp = await StemApp.inMemory(tasks: stemTasks);
  return createStemGeneratedWorkflowApp(stemApp: stemApp, registerTasks: false);
}
