import 'dart:convert';

import 'package:stem/stem.dart';
import 'package:stem_annotated_workflows/definitions.dart';

Future<void> main() async {
  final client = await StemClient.inMemory(module: stemModule);
  final app = await client.createWorkflowApp();

  final flowRunId = await StemWorkflowDefinitions.flow.start(app);
  final flowResult = await StemWorkflowDefinitions.flow.waitFor(
    app,
    flowRunId,
    timeout: const Duration(seconds: 2),
  );
  print('Flow result: ${jsonEncode(flowResult?.value)}');
  print(
    'Flow child workflow result: '
    '${jsonEncode(flowResult?.value?['childResult'])}',
  );

  final scriptResult = await StemWorkflowDefinitions.script.startAndWait(
    app,
    params: const WelcomeRequest(email: '  SomeEmail@Example.com  '),
    timeout: const Duration(seconds: 2),
  );
  print('Script result: ${jsonEncode(scriptResult?.value?.toJson())}');

  final scriptDetail = await app.viewRunDetail(scriptResult!.runId);
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

  final contextResult = await StemWorkflowDefinitions.contextScript
      .startAndWait(
        app,
        params: const WelcomeRequest(email: '  ContextEmail@Example.com  '),
        timeout: const Duration(seconds: 2),
      );
  print('Context script result: ${jsonEncode(contextResult?.value?.toJson())}');

  final contextDetail = await app.viewRunDetail(contextResult!.runId);
  final contextCheckpoints = contextDetail?.checkpoints
      .map((checkpoint) => checkpoint.baseCheckpointName)
      .join(' -> ');
  print('Context script checkpoints: $contextCheckpoints');
  print('Persisted context result: ${jsonEncode(contextDetail?.run.result)}');
  print('Context script detail: ${jsonEncode(contextDetail?.toJson())}');
  print(
    'Context child workflow result: '
    '${jsonEncode(contextResult.value!.childResult.toJson())}',
  );

  final typedTaskResult = await StemTaskDefinitions.sendEmailTyped
      .enqueueAndWait(
        app,
        const EmailDispatch(
          email: 'typed@example.com',
          subject: 'Welcome',
          body: 'Codec-backed DTO payloads',
          tags: ['welcome', 'transactional', 'annotated'],
        ),
        meta: const {'origin': 'annotated_workflows_example'},
        timeout: const Duration(seconds: 2),
      );
  print('Typed task result: ${jsonEncode(typedTaskResult?.value?.toJson())}');

  await app.close();
  await client.close();
}
