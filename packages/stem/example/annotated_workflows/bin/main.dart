import 'package:stem/stem.dart';
import 'package:stem_annotated_workflows/stem_registry.g.dart';

Future<void> main() async {
  final client = await StemClient.inMemory();
  registerStemDefinitions(
    workflows: client.workflowRegistry,
    tasks: client.taskRegistry,
  );
  final app = await client.createWorkflowApp(
    flows: stemFlows,
    scripts: stemScripts,
  );
  await app.start();

  final flowRunId = await app.startWorkflow('annotated.flow');
  final flowResult = await app.waitForCompletion<String>(
    flowRunId,
    timeout: const Duration(seconds: 2),
  );
  print('Flow result: ${flowResult?.value}');

  final scriptRunId = await app.startWorkflow('annotated.script');
  final scriptResult = await app.waitForCompletion<String>(
    scriptRunId,
    timeout: const Duration(seconds: 2),
  );
  print('Script result: ${scriptResult?.value}');

  await app.close();
  await client.close();
}
