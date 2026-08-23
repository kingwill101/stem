// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: unused_element, unnecessary_lambdas, omit_local_variable_types, unused_import

part of 'annotated_defs.dart';

final List<Flow> _stemFlows = <Flow>[];

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

final List<WorkflowScript> _stemScripts = <WorkflowScript>[
  WorkflowScript(
    name: "ecommerce.cart.add_item",
    checkpoints: [
      WorkflowCheckpoint(
        name: "validate-input",
        kind: WorkflowStepKind.task,
        taskNames: [],
      ),
      WorkflowCheckpoint(
        name: "price-line-item",
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

abstract final class StemWorkflowDefinitions {
  static final WorkflowRef<
    ({String cartId, String sku, int quantity}),
    Map<String, Object?>
  >
  addToCart =
      WorkflowRef<
        ({String cartId, String sku, int quantity}),
        Map<String, Object?>
      >(
        name: "ecommerce.cart.add_item",
        encodeParams: (params) => <String, Object?>{
          "cartId": params.cartId,
          "sku": params.sku,
          "quantity": params.quantity,
        },
      );
}

Object? _stemRequireArg(Map<String, Object?> args, String name) {
  if (!args.containsKey(name)) {
    throw ArgumentError('Missing required argument "$name".');
  }
  return args[name];
}

TaskInvocationContext _stemTaskInvocationContext(
  TaskExecutionContext context,
  Map<String, Object?> args,
) {
  if (context case final TaskInvocationContext value) {
    return value;
  }
  return TaskInvocationContext.local(
    id: context.id,
    args: args,
    headers: context.headers,
    meta: context.meta,
    attempt: context.attempt,
    heartbeat: context.heartbeat,
    extendLease: context.extendLease,
    progress: (percent, {data}) => context.progress(percent, data: data),
    cancellation: context.cancellation,
    enqueuer: context,
    workflows: context,
    workflowEvents: context,
  );
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

abstract final class StemTaskDefinitions {
  static final TaskDefinition<
    ({String event, String entityId, String detail}),
    Map<String, Object?>
  >
  ecommerceAuditLog =
      TaskDefinition<
        ({String event, String entityId, String detail}),
        Map<String, Object?>
      >(
        name: "ecommerce.audit.log",
        encodeArgs: (args) => <String, Object?>{
          "event": args.event,
          "entityId": args.entityId,
          "detail": args.detail,
        },
        decodeArgs: (args) => (
          event: (_stemRequireArg(args, "event") as String),
          entityId: (_stemRequireArg(args, "entityId") as String),
          detail: (_stemRequireArg(args, "detail") as String),
        ),
        defaultOptions: const TaskOptions(queue: "default"),
        metadata: const TaskMetadata(),
      );
}

final List<TypedTaskHandler<Object?, Object?>> _stemTasks =
    <TypedTaskHandler<Object?, Object?>>[
      StemTaskDefinitions.ecommerceAuditLog.handler(
        entrypoint: (context, args) => logAuditEvent(
          _stemTaskInvocationContext(
            context,
            StemTaskDefinitions.ecommerceAuditLog.encodeArgs(args),
          ),
          args.event,
          args.entityId,
          args.detail,
        ),
        executionMode: TaskExecutionMode.inline,
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
