// Workflow examples for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'package:stem/stem.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:stem_redis/stem_redis.dart';

// #region workflows-runtime
Future<void> bootstrapWorkflowRuntime() async {
  // #region workflows-app-create
  final workflowApp = await StemWorkflowApp.create(
    flows: [ApprovalsFlow.flow],
    scripts: [retryScript],
    broker: redisBrokerFactory('redis://127.0.0.1:56379'),
    backend: redisResultBackendFactory('redis://127.0.0.1:56379/1'),
    storeFactory: postgresWorkflowStoreFactory(
      'postgresql://postgres:postgres@127.0.0.1:65432/stem',
    ),
    eventBusFactory: WorkflowEventBusFactory.inMemory(),
    workerConfig: const StemWorkerConfig(queue: 'workflow'),
  );
  // #endregion workflows-app-create

  // #region workflows-app-start
  await workflowApp.start();
  // #endregion workflows-app-start
}
// #endregion workflows-runtime

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
        final resume = ctx.takeResumeData() as Map<String, Object?>?;
        if (resume == null) {
          await ctx.awaitEvent('approvals.manager');
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
}

Future<void> registerFlow(StemWorkflowApp workflowApp) async {
  workflowApp.runtime.registerWorkflow(ApprovalsFlow.flow.definition);
}
// #endregion workflows-flow

// #region workflows-script
final retryScript = WorkflowScript(
  name: 'billing.retry-script',
  run: (script) async {
    final chargeId = await script.step<String>('charge', (ctx) async {
      final resume = ctx.takeResumeData() as Map<String, Object?>?;
      if (resume == null) {
        await ctx.awaitEvent('billing.charge.prepared');
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
// #endregion workflows-script

// #region workflows-run
Future<void> runWorkflow(StemWorkflowApp workflowApp) async {
  final runId = await workflowApp.startWorkflow(
    'approvals.flow',
    params: {
      'draft': {'documentId': 'doc-42'},
    },
    cancellationPolicy: const WorkflowCancellationPolicy(
      maxRunDuration: Duration(hours: 2),
      maxSuspendDuration: Duration(minutes: 30),
    ),
  );

  final result = await workflowApp.waitForCompletion<String>(
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
  final app = await StemWorkflowApp.create(
    flows: [ApprovalsFlow.flow],
    encoderRegistry: encoders,
    additionalEncoders: const [GzipPayloadEncoder()],
  );

  await app.close();
}
// #endregion workflows-encoders

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
  await app.start();

  final runId = await app.startWorkflow('demo.flow');
  final result = await app.waitForCompletion<String>(
    runId,
    timeout: const Duration(seconds: 5),
  );
  print('Workflow result: ${result?.status} value=${result?.value}');

  await app.close();
}
