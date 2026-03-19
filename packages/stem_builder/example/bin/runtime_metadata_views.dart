import 'dart:convert';

import 'package:stem/stem.dart';
import 'package:stem_builder_example/definitions.dart';

Future<void> main() async {
  final app = await StemWorkflowApp.inMemory(module: stemModule);
  final runtime = app.runtime;

  try {
    print('--- Generated manifest (builder output) ---');
    print(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(stemModule.workflowManifest.map((entry) => entry.toJson()).toList()),
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

    final flowRunId = await StemWorkflowDefinitions.flow
        .call(const {'name': 'runtime metadata'})
        .startWithRuntime(runtime);
    await runtime.executeRun(flowRunId);

    final scriptRunId = await StemWorkflowDefinitions.userSignup
        .call((email: 'dev@stem.dev'))
        .startWithRuntime(runtime);
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
