// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: unused_element, unnecessary_lambdas, omit_local_variable_types, unused_import

part of 'definitions.dart';

final List<Flow> _stemFlows = <Flow>[
  Flow(
    name: "builder.example.flow",
    build: (flow) {
      final impl = BuilderExampleFlow();
      flow.step<String>(
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

final List<WorkflowScript> _stemScripts = <WorkflowScript>[
  WorkflowScript(
    name: "builder.example.user_signup",
    checkpoints: [
      WorkflowCheckpoint(
        name: "create-user",
        kind: WorkflowStepKind.task,
        taskNames: [],
      ),
      WorkflowCheckpoint(
        name: "send-welcome-email",
        kind: WorkflowStepKind.task,
        taskNames: [],
      ),
      WorkflowCheckpoint(
        name: "send-one-week-check-in-email",
        kind: WorkflowStepKind.task,
        taskNames: [],
      ),
    ],
    run: (script) => _StemScriptProxy0(
      script,
    ).run((_stemRequireArg(script.params, "email") as String)),
  ),
];

abstract final class StemWorkflowDefinitions {
  static final WorkflowRef<Map<String, Object?>, String> flow =
      WorkflowRef<Map<String, Object?>, String>(
        name: "builder.example.flow",
        encodeParams: (params) => params,
      );
  static final WorkflowRef<({String email}), Map<String, Object?>> userSignup =
      WorkflowRef<({String email}), Map<String, Object?>>(
        name: "builder.example.user_signup",
        encodeParams: (params) => <String, Object?>{"email": params.email},
      );
}

Object? _stemRequireArg(Map<String, Object?> args, String name) {
  if (!args.containsKey(name)) {
    throw ArgumentError('Missing required argument "$name".');
  }
  return args[name];
}

abstract final class StemTaskDefinitions {
  static final TaskDefinition<Map<String, Object?>, Object?>
  builderExampleTask = TaskDefinition<Map<String, Object?>, Object?>(
    name: "builder.example.task",
    encodeArgs: (args) => args,
    defaultOptions: const TaskOptions(),
    metadata: const TaskMetadata(),
  );
}

extension StemGeneratedTaskEnqueuer on TaskEnqueuer {
  Future<String> enqueueBuilderExampleTask({
    required Map<String, Object?> args,
    Map<String, String> headers = const {},
    TaskOptions? options,
    DateTime? notBefore,
    Map<String, Object?>? meta,
    TaskEnqueueOptions? enqueueOptions,
  }) {
    return enqueueCall(
      StemTaskDefinitions.builderExampleTask.call(
        args,
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
  Future<TaskResult<Object?>?> waitForBuilderExampleTask(
    String taskId, {
    Duration? timeout,
  }) {
    return waitForTaskDefinition(
      taskId,
      StemTaskDefinitions.builderExampleTask,
      timeout: timeout,
    );
  }
}

final List<TaskHandler<Object?>> _stemTasks = <TaskHandler<Object?>>[
  FunctionTaskHandler<Object?>(
    name: "builder.example.task",
    entrypoint: builderExampleTask,
    options: const TaskOptions(),
    metadata: const TaskMetadata(),
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
