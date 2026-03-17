// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: unused_element, unnecessary_lambdas, omit_local_variable_types, unused_import

part of 'annotated_defs.dart';

final List<Flow> stemFlows = <Flow>[];

class _StemScriptProxy0 extends AddToCartWorkflow {
  _StemScriptProxy0(this._script);
  final WorkflowScriptContext _script;
  @override
  Future<Map<String, Object?>> validateInput(
    String cartId,
    String sku,
    int quantity,
  ) {
    return _script.step<Map<String, Object?>>(
      "validate-input",
      (context) => super.validateInput(cartId, sku, quantity),
    );
  }

  @override
  Future<Map<String, Object?>> priceLineItem(
    String cartId,
    String sku,
    int quantity,
  ) {
    return _script.step<Map<String, Object?>>(
      "price-line-item",
      (context) => super.priceLineItem(cartId, sku, quantity),
    );
  }
}

final List<WorkflowScript> stemScripts = <WorkflowScript>[
  WorkflowScript(
    name: "ecommerce.cart.add_item",
    steps: [
      FlowStep(
        name: "validate-input",
        handler: _stemScriptManifestStepNoop,
        kind: WorkflowStepKind.task,
        taskNames: [],
      ),
      FlowStep(
        name: "price-line-item",
        handler: _stemScriptManifestStepNoop,
        kind: WorkflowStepKind.task,
        taskNames: [],
      ),
    ],
    description: "Validates cart item requests and computes durable pricing.",
    run: (script) => _StemScriptProxy0(script).run(
      (_stemRequireArg(script.params, "cartId") as String),
      (_stemRequireArg(script.params, "sku") as String),
      (_stemRequireArg(script.params, "quantity") as int),
    ),
  ),
];

abstract final class StemWorkflowNames {
  static const String addToCart = "ecommerce.cart.add_item";
}

extension StemGeneratedWorkflowAppStarters on StemWorkflowApp {
  Future<String> startAddToCart({
    required String cartId,
    required String sku,
    required int quantity,
    Map<String, Object?> extraParams = const {},
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    final params = <String, Object?>{
      ...extraParams,
      "cartId": cartId,
      "sku": sku,
      "quantity": quantity,
    };
    return startWorkflow(
      StemWorkflowNames.addToCart,
      params: params,
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    );
  }
}

extension StemGeneratedWorkflowRuntimeStarters on WorkflowRuntime {
  Future<String> startAddToCart({
    required String cartId,
    required String sku,
    required int quantity,
    Map<String, Object?> extraParams = const {},
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    final params = <String, Object?>{
      ...extraParams,
      "cartId": cartId,
      "sku": sku,
      "quantity": quantity,
    };
    return startWorkflow(
      StemWorkflowNames.addToCart,
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
    logAuditEvent(
      context,
      (_stemRequireArg(args, "event") as String),
      (_stemRequireArg(args, "entityId") as String),
      (_stemRequireArg(args, "detail") as String),
    ),
  );
}

final List<TaskHandler<Object?>> stemTasks = <TaskHandler<Object?>>[
  FunctionTaskHandler<Object?>(
    name: "ecommerce.audit.log",
    entrypoint: _stemTaskAdapter0,
    options: const TaskOptions(queue: "default"),
    metadata: const TaskMetadata(),
    runInIsolate: false,
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
