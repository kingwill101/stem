import 'dart:convert';

import 'package:stem_builder_example/stem_registry.g.dart';

Future<void> main() async {
  final app = await createStemGeneratedInMemoryApp();
  final runtime = app.runtime;

  try {
    print('--- Generated manifest (builder output) ---');
    print(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(stemWorkflowManifest.map((entry) => entry.toJson()).toList()),
    );

    print('\n--- Runtime manifest (registered definitions) ---');
    print(
      const JsonEncoder.withIndent('  ').convert(
        runtime
            .workflowManifest()
            .map((entry) => entry.toJson())
            .toList(growable: false),
      ),
    );

    final flowRunId = await runtime.startBuilderExampleFlow(
      params: const {'name': 'runtime metadata'},
    );
    await runtime.executeRun(flowRunId);

    final scriptRunId = await runtime.startBuilderExampleUserSignup(
      email: 'dev@stem.dev',
    );
    await runtime.executeRun(scriptRunId);

    final runViews = await runtime.listRunViews(limit: 10);
    print('\n--- Run views ---');
    print(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(runViews.map((view) => view.toJson()).toList()),
    );

    final flowDetail = await runtime.viewRunDetail(flowRunId);
    final scriptDetail = await runtime.viewRunDetail(scriptRunId);

    print('\n--- Flow run detail ---');
    print(const JsonEncoder.withIndent('  ').convert(flowDetail?.toJson()));

    print('\n--- Script run detail ---');
    print(const JsonEncoder.withIndent('  ').convert(scriptDetail?.toJson()));
  } finally {
    await app.close();
  }
}
