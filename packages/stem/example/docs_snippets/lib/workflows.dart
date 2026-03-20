// Workflow examples for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'package:stem/stem.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:stem_redis/stem_redis.dart';

class ApprovalDraft {
  const ApprovalDraft({required this.documentId});

  final String documentId;

  Map<String, Object?> toJson() => {'documentId': documentId};

  factory ApprovalDraft.fromJson(Map<String, Object?> json) {
    return ApprovalDraft(documentId: json['documentId'] as String);
  }
}

const approvalDraftCodec = PayloadCodec<ApprovalDraft>.map(
  encode: _encodeApprovalDraft,
  decode: ApprovalDraft.fromJson,
  typeName: 'ApprovalDraft',
);

Object? _encodeApprovalDraft(ApprovalDraft value) => value.toJson();

// #region workflows-runtime
Future<void> bootstrapWorkflowApp() async {
  // #region workflows-app-create
  final workflowApp = await StemWorkflowApp.fromUrl(
    'redis://127.0.0.1:56379',
    adapters: const [StemRedisAdapter(), StemPostgresAdapter()],
    overrides: const StemStoreOverrides(
      backend: 'redis://127.0.0.1:56379/1',
      workflow: 'postgresql://<user>:<password>@127.0.0.1:65432/stem',
    ),
    flows: [ApprovalsFlow.flow],
    scripts: [retryScript],
    eventBusFactory: WorkflowEventBusFactory.inMemory(),
    workerConfig: const StemWorkerConfig(queue: 'workflow'),
  );
  // #endregion workflows-app-create

  // #region workflows-app-start
  await workflowApp.start();
  // #endregion workflows-app-start
}
// #endregion workflows-runtime

// #region workflows-client
Future<void> bootstrapWorkflowClient() async {
  final client = await StemClient.fromUrl('memory://', module: stemModule);
  final app = await client.createWorkflowApp();
  await app.close();
  await client.close();
}
// #endregion workflows-client

// #region workflows-flow
class ApprovalsFlow {
  static final flow = Flow<String>(
    name: 'approvals.flow',
    build: (flow) {
      flow.step('draft', (ctx) async {
        final payload = ctx.params['draft'] as Map<String, Object?>;
        return payload['documentId'];
      });

      flow.step('manager-review', (ctx) async {
        final resume = ctx.waitForEventValue<Map<String, Object?>>(
          'approvals.manager',
        );
        if (resume == null) {
          return null;
        }
        return resume['approvedBy'] as String?;
      });

      flow.step('finalize', (ctx) async {
        final approvedBy = ctx.previousResult as String?;
        return 'approved-by:$approvedBy';
      });
    },
  );

  static final ref = flow.refWithCodec<ApprovalDraft>(
    paramsCodec: approvalDraftCodec,
  );
}

Future<void> registerFlow(StemWorkflowApp workflowApp) async {
  workflowApp.registerFlows([ApprovalsFlow.flow]);
}

Future<void> registerWorkflowDefinition(StemWorkflowApp workflowApp) async {
  workflowApp.registerWorkflows([ApprovalsFlow.flow.definition]);
}
// #endregion workflows-flow

// #region workflows-script
final retryScript = WorkflowScript(
  name: 'billing.retry-script',
  run: (script) async {
    final chargeId = await script.step<String>('charge', (ctx) async {
      final resume = ctx.waitForEventValue<Map<String, Object?>>(
        'billing.charge.prepared',
      );
      if (resume == null) {
        return 'pending';
      }
      return resume['chargeId'] as String;
    });

    final receipt = await script.step<String>('confirm', (ctx) async {
      ctx.idempotencyKey('confirm-$chargeId');
      return 'receipt-$chargeId';
    });

    return receipt;
  },
);

final retryDefinition = retryScript.definition;

Future<void> registerScript(StemWorkflowApp workflowApp) async {
  workflowApp.registerScripts([retryScript]);
}
// #endregion workflows-script

// #region workflows-run
Future<void> runWorkflow(StemWorkflowApp workflowApp) async {
  final runId = await ApprovalsFlow.ref.startWith(
    workflowApp,
    const ApprovalDraft(documentId: 'doc-42'),
    cancellationPolicy: const WorkflowCancellationPolicy(
      maxRunDuration: Duration(hours: 2),
      maxSuspendDuration: Duration(minutes: 30),
    ),
  );

  final result = await ApprovalsFlow.ref.waitFor(
    workflowApp,
    runId,
    timeout: const Duration(minutes: 5),
  );

  if (result?.isCompleted == true) {
    print('Workflow finished with ${result!.value}');
  } else {
    print('Workflow state: ${result?.status}');
  }
}
// #endregion workflows-run

// #region workflows-encoders
final encoders = TaskPayloadEncoderRegistry(
  defaultArgsEncoder: const JsonTaskPayloadEncoder(),
  defaultResultEncoder: const Base64PayloadEncoder(),
);

Future<void> configureWorkflowEncoders() async {
  final app = await StemWorkflowApp.fromUrl(
    'memory://',
    flows: [ApprovalsFlow.flow],
    encoderRegistry: encoders,
    additionalEncoders: const [GzipPayloadEncoder()],
  );

  await app.close();
}
// #endregion workflows-encoders

// #region workflows-annotated
@WorkflowDefn(name: 'approvals.flow')
class ApprovalsAnnotatedWorkflow {
  @WorkflowStep()
  Future<String> draft({FlowContext? context}) async {
    final ctx = context!;
    final payload = ctx.params['draft'] as Map<String, Object?>;
    return payload['documentId'] as String;
  }

  @WorkflowStep(name: 'manager-review')
  Future<String?> managerReview({FlowContext? context}) async {
    final ctx = context!;
    final resume = ctx.waitForEventValue<Map<String, Object?>>(
      'approvals.manager',
    );
    if (resume == null) {
      return null;
    }
    return resume['approvedBy'] as String?;
  }

  @WorkflowStep()
  Future<String> finalize({FlowContext? context}) async {
    final ctx = context!;
    final approvedBy = ctx.previousResult as String?;
    return 'approved-by:$approvedBy';
  }
}

@WorkflowDefn(name: 'billing.retry-script', kind: WorkflowKind.script)
class BillingRetryAnnotatedWorkflow {
  Future<String> run({WorkflowScriptContext? context}) async {
    final script = context!;
    final chargeId = await script.step<String>('charge', (ctx) async {
      final resume = ctx.waitForEventValue<Map<String, Object?>>(
        'billing.charge.prepared',
      );
      if (resume == null) {
        return 'pending';
      }
      return resume['chargeId'] as String;
    });

    return script.step<String>('confirm', (ctx) async {
      ctx.idempotencyKey('confirm-$chargeId');
      return 'receipt-$chargeId';
    });
  }
}

@TaskDefn(
  name: 'send_email',
  options: TaskOptions(maxRetries: 5),
)
Future<void> sendEmail(
  Map<String, Object?> args, {
  TaskInvocationContext? context,
}) async {
  final ctx = context!;
  ctx.heartbeat();
  // send email
}

Future<void> registerAnnotatedDefinitions(StemWorkflowApp app) async {
  // Generated by stem_builder.
  app.registerModule(stemModule);
}
// #endregion workflows-annotated

// Stub for docs snippet; generated by stem_builder in real apps.
final StemModule stemModule = StemModule();

class Base64PayloadEncoder extends TaskPayloadEncoder {
  const Base64PayloadEncoder();

  @override
  Object? encode(Object? value) => value;

  @override
  Object? decode(Object? stored) => stored;
}

class GzipPayloadEncoder extends TaskPayloadEncoder {
  const GzipPayloadEncoder();

  @override
  Object? encode(Object? value) => value;

  @override
  Object? decode(Object? stored) => stored;
}

Future<void> main() async {
  final demoFlow = Flow<String>(
    name: 'demo.flow',
    build: (flow) {
      flow.step('hello', (ctx) async => 'done');
    },
  );

  final app = await StemWorkflowApp.inMemory(flows: [demoFlow]);

  final runId = await demoFlow.startWith(app);
  final result = await demoFlow.waitFor(
    app,
    runId,
    timeout: const Duration(seconds: 5),
  );
  print('Workflow result: ${result?.status} value=${result?.value}');

  await app.close();
}
