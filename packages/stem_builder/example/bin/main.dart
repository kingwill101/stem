import 'dart:convert';

import 'package:stem_builder_example/definitions.dart';

Future<void> main() async {
  print('Registered workflows:');
  for (final entry in stemWorkflowManifest) {
    print(' - ${entry.name} (id=${entry.id})');
  }

  print('\nGenerated workflow manifest:');
  print(
    const JsonEncoder.withIndent(
      '  ',
    ).convert(stemWorkflowManifest.map((entry) => entry.toJson()).toList()),
  );

  final app = await createStemGeneratedInMemoryApp();
  try {
    final runtime = app.runtime;
    final runtimeManifest = runtime
        .workflowManifest()
        .map((entry) => entry.toJson())
        .toList(growable: false);
    print('\nRuntime manifest:');
    print(const JsonEncoder.withIndent('  ').convert(runtimeManifest));

    final runId = await runtime.startFlow(
      params: const {'name': 'Stem Builder'},
    );
    await runtime.executeRun(runId);
    final result = await runtime.viewRun(runId);
    print('\nFlow result: ${result?.result}');
  } finally {
    await app.close();
  }
}
