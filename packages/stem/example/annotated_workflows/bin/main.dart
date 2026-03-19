import 'dart:convert';

import 'package:stem/stem.dart';
import 'package:stem_annotated_workflows/definitions.dart';

Future<void> main() async {
  final client = await StemClient.inMemory();
  final app = await client.createWorkflowApp(
    module: stemModule,
    workerConfig: StemWorkerConfig(
      queue: 'workflow',
      subscription: RoutingSubscription(queues: ['workflow', 'default']),
    ),
  );
  await app.start();

  final flowRunId = await StemWorkflowDefinitions.flow
      .call(const <String, Object?>{})
      .startWithApp(app);
  final flowResult = await StemWorkflowDefinitions.flow.waitFor(
    app,
    flowRunId,
    timeout: const Duration(seconds: 2),
  );
  print('Flow result: ${jsonEncode(flowResult?.value)}');

  final scriptCall = StemWorkflowDefinitions.script.call(
    (request: const WelcomeRequest(email: '  SomeEmail@Example.com  ')),
  );
  final scriptResult = await scriptCall.startAndWaitWithApp(
    app,
    timeout: const Duration(seconds: 2),
  );
  print('Script result: ${jsonEncode(scriptResult?.value?.toJson())}');

  final scriptDetail = await app.runtime.viewRunDetail(scriptResult!.runId);
  final scriptCheckpoints = scriptDetail?.steps
      .map((step) => step.baseStepName)
      .join(' -> ');
  final persistedPreparation = scriptDetail?.steps
      .firstWhere((step) => step.baseStepName == 'prepare-welcome')
      .value;
  print('Script checkpoints: $scriptCheckpoints');
  print(
    'Persisted prepare-welcome checkpoint: ${jsonEncode(persistedPreparation)}',
  );
  print('Persisted script result: ${jsonEncode(scriptDetail?.run.result)}');
  print('Script detail: ${jsonEncode(scriptDetail?.toJson())}');

  final contextCall = StemWorkflowDefinitions.contextScript.call(
    (request: const WelcomeRequest(email: '  ContextEmail@Example.com  ')),
  );
  final contextResult = await contextCall.startAndWaitWithApp(
    app,
    timeout: const Duration(seconds: 2),
  );
  print('Context script result: ${jsonEncode(contextResult?.value?.toJson())}');

  final contextDetail = await app.runtime.viewRunDetail(contextResult!.runId);
  final contextCheckpoints = contextDetail?.steps
      .map((step) => step.baseStepName)
      .join(' -> ');
  print('Context script checkpoints: $contextCheckpoints');
  print('Persisted context result: ${jsonEncode(contextDetail?.run.result)}');
  print('Context script detail: ${jsonEncode(contextDetail?.toJson())}');

  final typedTaskId = await app.app.stem.enqueueSendEmailTyped(
    dispatch: const EmailDispatch(
      email: 'typed@example.com',
      subject: 'Welcome',
      body: 'Codec-backed DTO payloads',
      tags: ['welcome', 'transactional', 'annotated'],
    ),
    meta: const {'origin': 'annotated_workflows_example'},
  );
  final typedTaskResult = await app.app.stem.waitForSendEmailTyped(
    typedTaskId,
    timeout: const Duration(seconds: 2),
  );
  print('Typed task result: ${jsonEncode(typedTaskResult?.value?.toJson())}');

  await app.close();
  await client.close();
}
