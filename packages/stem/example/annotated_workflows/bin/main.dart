import 'dart:convert';

import 'package:stem/stem.dart';
import 'package:stem_annotated_workflows/definitions.dart';

Future<void> main() async {
  final client = await StemClient.inMemory();
  final app = await client.createWorkflowApp(module: stemModule);
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
  final flowChildRunId = flowResult?.value?['childRunId'] as String?;
  if (flowChildRunId != null) {
    final flowChildResult = await StemWorkflowDefinitions.script.waitFor(
      app,
      flowChildRunId,
      timeout: const Duration(seconds: 2),
    );
    print(
      'Flow child workflow result: '
      '${jsonEncode(flowChildResult?.value?.toJson())}',
    );
  }

  final scriptCall = StemWorkflowDefinitions.script.call((
    request: const WelcomeRequest(email: '  SomeEmail@Example.com  '),
  ));
  final scriptResult = await scriptCall.startAndWaitWithApp(
    app,
    timeout: const Duration(seconds: 2),
  );
  print('Script result: ${jsonEncode(scriptResult?.value?.toJson())}');

  final scriptDetail = await app.runtime.viewRunDetail(scriptResult!.runId);
  final scriptCheckpoints = scriptDetail?.checkpoints
      .map((checkpoint) => checkpoint.baseCheckpointName)
      .join(' -> ');
  final persistedPreparation = scriptDetail?.checkpoints
      .firstWhere(
        (checkpoint) => checkpoint.baseCheckpointName == 'prepare-welcome',
      )
      .value;
  print('Script checkpoints: $scriptCheckpoints');
  print(
    'Persisted prepare-welcome checkpoint: ${jsonEncode(persistedPreparation)}',
  );
  print('Persisted script result: ${jsonEncode(scriptDetail?.run.result)}');
  print('Script detail: ${jsonEncode(scriptDetail?.toJson())}');

  final contextCall = StemWorkflowDefinitions.contextScript.call((
    request: const WelcomeRequest(email: '  ContextEmail@Example.com  '),
  ));
  final contextResult = await contextCall.startAndWaitWithApp(
    app,
    timeout: const Duration(seconds: 2),
  );
  print('Context script result: ${jsonEncode(contextResult?.value?.toJson())}');

  final contextDetail = await app.runtime.viewRunDetail(contextResult!.runId);
  final contextCheckpoints = contextDetail?.checkpoints
      .map((checkpoint) => checkpoint.baseCheckpointName)
      .join(' -> ');
  print('Context script checkpoints: $contextCheckpoints');
  print('Persisted context result: ${jsonEncode(contextDetail?.run.result)}');
  print('Context script detail: ${jsonEncode(contextDetail?.toJson())}');
  final contextChildResult = await StemWorkflowDefinitions.script.waitFor(
    app,
    contextResult.value!.childRunId,
    timeout: const Duration(seconds: 2),
  );
  print(
    'Context child workflow result: '
    '${jsonEncode(contextChildResult?.value?.toJson())}',
  );

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
