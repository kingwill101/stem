import 'dart:convert';

import 'package:stem/stem.dart';
import 'package:stem_annotated_workflows/definitions.dart';

Future<void> main() async {
  final client = await StemClient.inMemory();
  registerStemDefinitions(
    workflows: client.workflowRegistry,
    tasks: client.taskRegistry,
  );
  final app = await client.createWorkflowApp(
    flows: stemFlows,
    scripts: stemScripts,
    workerConfig: StemWorkerConfig(
      queue: 'workflow',
      subscription: RoutingSubscription(queues: ['workflow', 'default']),
    ),
  );
  await app.start();

  final flowRunId = await app.startFlow();
  final flowResult = await app.waitForCompletion<Map<String, Object?>>(
    flowRunId,
    timeout: const Duration(seconds: 2),
  );
  print('Flow result: ${jsonEncode(flowResult?.value)}');

  final scriptRunId = await app.startScript(email: '  SomeEmail@Example.com  ');
  final scriptResult = await app.waitForCompletion<Map<String, Object?>>(
    scriptRunId,
    timeout: const Duration(seconds: 2),
  );
  print('Script result: ${jsonEncode(scriptResult?.value)}');

  final scriptDetail = await app.runtime.viewRunDetail(scriptRunId);
  final scriptCheckpoints = scriptDetail?.steps
      .map((step) => step.baseStepName)
      .join(' -> ');
  print('Script checkpoints: $scriptCheckpoints');
  print('Script detail: ${jsonEncode(scriptDetail?.toJson())}');

  final contextRunId = await app.startContextScript(
    email: '  ContextEmail@Example.com  ',
  );
  final contextResult = await app.waitForCompletion<Map<String, Object?>>(
    contextRunId,
    timeout: const Duration(seconds: 2),
  );
  print('Context script result: ${jsonEncode(contextResult?.value)}');

  final contextDetail = await app.runtime.viewRunDetail(contextRunId);
  final contextCheckpoints = contextDetail?.steps
      .map((step) => step.baseStepName)
      .join(' -> ');
  print('Context script checkpoints: $contextCheckpoints');
  print('Context script detail: ${jsonEncode(contextDetail?.toJson())}');

  final typedTaskId = await app.app.stem.enqueue(
    'send_email_typed',
    args: {
      'email': 'typed@example.com',
      'message': {'subject': 'Welcome', 'body': 'Serializable payloads only'},
      'tags': [
        'welcome',
        1,
        true,
        {'channel': 'email'},
      ],
    },
    meta: const {'origin': 'annotated_workflows_example'},
  );
  final typedTaskResult = await app.app.stem.waitForTask<Map<String, Object?>>(
    typedTaskId,
    timeout: const Duration(seconds: 2),
  );
  print('Typed task result: ${jsonEncode(typedTaskResult?.value)}');

  await app.close();
  await client.close();
}
