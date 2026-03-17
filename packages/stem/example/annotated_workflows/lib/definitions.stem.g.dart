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

final List<WorkflowScript> stemScripts = <WorkflowScript>[
  WorkflowScript(
    name: "annotated.script",
    run: (script) => AnnotatedScriptWorkflow().run(script),
  ),
];

abstract final class StemWorkflowNames {
  static const String flow = "annotated.flow";
  static const String script = "annotated.script";
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
    Map<String, Object?> params = const {},
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    return startWorkflow(
      StemWorkflowNames.script,
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
    Map<String, Object?> params = const {},
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    return startWorkflow(
      StemWorkflowNames.script,
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

final List<TaskHandler<Object?>> stemTasks = <TaskHandler<Object?>>[
  FunctionTaskHandler<Object?>(
    name: "send_email",
    entrypoint: sendEmail,
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
