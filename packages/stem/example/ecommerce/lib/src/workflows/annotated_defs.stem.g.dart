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
  static Future<String> startAddToCart(
    WorkflowCaller caller, {
    required String cartId,
    required String sku,
    required int quantity,
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    return addToCart
        .call(
          (cartId: cartId, sku: sku, quantity: quantity),
          parentRunId: parentRunId,
          ttl: ttl,
          cancellationPolicy: cancellationPolicy,
        )
        .startWith(caller);
  }

  static Future<WorkflowResult<Map<String, Object?>>?> startAndWaitAddToCart(
    WorkflowCaller caller, {
    required String cartId,
    required String sku,
    required int quantity,
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) {
    return addToCart
        .call(
          (cartId: cartId, sku: sku, quantity: quantity),
          parentRunId: parentRunId,
          ttl: ttl,
          cancellationPolicy: cancellationPolicy,
        )
        .startAndWaitWith(caller, pollInterval: pollInterval, timeout: timeout);
  }

  static Future<WorkflowResult<Map<String, Object?>>?> waitForAddToCart(
    WorkflowCaller caller,
    String runId, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) {
    return addToCart.waitForWith(
      caller,
      runId,
      pollInterval: pollInterval,
      timeout: timeout,
    );
  }
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
        defaultOptions: const TaskOptions(queue: "default"),
        metadata: const TaskMetadata(),
      );
  static Future<String> enqueueEcommerceAuditLog(
    TaskEnqueuer enqueuer, {
    required String event,
    required String entityId,
    required String detail,
    Map<String, String> headers = const {},
    TaskOptions? options,
    DateTime? notBefore,
    Map<String, Object?>? meta,
    TaskEnqueueOptions? enqueueOptions,
  }) {
    return ecommerceAuditLog
        .call(
          (event: event, entityId: entityId, detail: detail),
          headers: headers,
          options: options,
          notBefore: notBefore,
          meta: meta,
          enqueueOptions: enqueueOptions,
        )
        .enqueueWith(enqueuer, enqueueOptions: enqueueOptions);
  }

  static Future<TaskResult<Map<String, Object?>>?>
  enqueueAndWaitEcommerceAuditLog(
    Stem stem, {
    required String event,
    required String entityId,
    required String detail,
    Map<String, String> headers = const {},
    TaskOptions? options,
    DateTime? notBefore,
    Map<String, Object?>? meta,
    TaskEnqueueOptions? enqueueOptions,
    Duration? timeout,
  }) async {
    final taskId = await enqueueEcommerceAuditLog(
      stem,
      event: event,
      entityId: entityId,
      detail: detail,
      headers: headers,
      options: options,
      notBefore: notBefore,
      meta: meta,
      enqueueOptions: enqueueOptions,
    );
    return ecommerceAuditLog.waitFor(stem, taskId, timeout: timeout);
  }
}

final List<TaskHandler<Object?>> _stemTasks = <TaskHandler<Object?>>[
  FunctionTaskHandler<Object?>(
    name: "ecommerce.audit.log",
    entrypoint: _stemTaskAdapter0,
    options: const TaskOptions(queue: "default"),
    metadata: const TaskMetadata(),
    runInIsolate: false,
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
