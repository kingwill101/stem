// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: unused_element, unnecessary_lambdas, omit_local_variable_types, unused_import

part of 'definitions.dart';

final List<Flow> stemFlows = <Flow>[
  Flow(
    name: "builder.example.flow",
    build: (flow) {
      final impl = BuilderExampleFlow();
      flow.step(
        "greet",
        (ctx) => impl.greet((_stemRequireArg(ctx.params, "name") as String)),
        kind: WorkflowStepKind.task,
        taskNames: [],
      );
    },
  ),
];

class _StemScriptProxy0 extends BuilderUserSignupWorkflow {
  _StemScriptProxy0(this._script);
  final WorkflowScriptContext _script;
  @override
  Future<Map<String, Object?>> createUser(String email) {
    return _script.step<Map<String, Object?>>(
      "create-user",
      (context) => super.createUser(email),
    );
  }

  @override
  Future<void> sendWelcomeEmail(String email) {
    return _script.step<void>(
      "send-welcome-email",
      (context) => super.sendWelcomeEmail(email),
    );
  }

  @override
  Future<void> sendOneWeekCheckInEmail(String email) {
    return _script.step<void>(
      "send-one-week-check-in-email",
      (context) => super.sendOneWeekCheckInEmail(email),
    );
  }
}

final List<WorkflowScript> stemScripts = <WorkflowScript>[
  WorkflowScript(
    name: "builder.example.user_signup",
    steps: [
      FlowStep(
        name: "create-user",
        handler: _stemScriptManifestStepNoop,
        kind: WorkflowStepKind.task,
        taskNames: [],
      ),
      FlowStep(
        name: "send-welcome-email",
        handler: _stemScriptManifestStepNoop,
        kind: WorkflowStepKind.task,
        taskNames: [],
      ),
      FlowStep(
        name: "send-one-week-check-in-email",
        handler: _stemScriptManifestStepNoop,
        kind: WorkflowStepKind.task,
        taskNames: [],
      ),
    ],
    run: (script) => _StemScriptProxy0(
      script,
    ).run((_stemRequireArg(script.params, "email") as String)),
  ),
];

abstract final class StemWorkflowNames {
  static const String flow = "builder.example.flow";
  static const String userSignup = "builder.example.user_signup";
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

  Future<String> startUserSignup({
    required String email,
    Map<String, Object?> extraParams = const {},
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    final params = <String, Object?>{...extraParams, "email": email};
    return startWorkflow(
      StemWorkflowNames.userSignup,
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

  Future<String> startUserSignup({
    required String email,
    Map<String, Object?> extraParams = const {},
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    final params = <String, Object?>{...extraParams, "email": email};
    return startWorkflow(
      StemWorkflowNames.userSignup,
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

final List<TaskHandler<Object?>> stemTasks = <TaskHandler<Object?>>[
  FunctionTaskHandler<Object?>(
    name: "builder.example.task",
    entrypoint: builderExampleTask,
    options: const TaskOptions(),
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
