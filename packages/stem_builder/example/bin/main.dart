import 'dart:convert';

import 'package:stem/stem.dart';
import 'package:stem_builder_example/definitions.dart';

Future<void> main() async {
  print('Registered workflows:');
  for (final entry in stemModule.workflowManifest) {
    print(' - ${entry.name} (id=${entry.id})');
  }

  print('\nGenerated workflow manifest:');
  print(
    const JsonEncoder.withIndent(
      '  ',
    ).convert(stemModule.workflowManifest.map((entry) => entry.toJson()).toList()),
  );

  final app = await StemWorkflowApp.inMemory(module: stemModule);
  try {
    final runtime = app.runtime;
    final runtimeManifest = runtime
        .workflowManifest()
        .map((entry) => entry.toJson())
        .toList(growable: false);
    print('\nRuntime manifest:');
    print(const JsonEncoder.withIndent('  ').convert(runtimeManifest));

    final runId = await StemWorkflowDefinitions.flow.startWith(
      runtime,
      'Stem Builder',
    );
    await runtime.executeRun(runId);
    final result = await StemWorkflowDefinitions.flow.waitFor(
      app,
      runId,
      timeout: const Duration(seconds: 2),
    );
    print('\nFlow result: ${result?.value}');
  } finally {
    await app.close();
  }

  final taskApp = await StemApp.inMemory(module: stemModule);
  try {
    final taskResult = await StemTaskDefinitions.builderExamplePing
        .enqueueAndWait(
      taskApp,
      timeout: const Duration(seconds: 2),
    );
    print('\nNo-arg task result: ${taskResult?.value}');
  } finally {
    await taskApp.shutdown();
  }
}
