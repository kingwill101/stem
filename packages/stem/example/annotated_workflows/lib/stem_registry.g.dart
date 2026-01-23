// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: unused_element, unnecessary_lambdas, omit_local_variable_types

import 'package:stem/stem.dart';
import 'package:stem_annotated_workflows/definitions.dart';

final List<Flow> stemFlows = <Flow>[
  Flow(
    name: 'annotated.flow',
    build: (flow) {
      final impl = AnnotatedFlowWorkflow();
      flow.step(
        'start',
        (ctx) => impl.start(ctx),
      );
    },
  ),
];

final List<WorkflowScript> stemScripts = <WorkflowScript>[
  WorkflowScript(
    name: 'annotated.script',
    run: (script) => AnnotatedScriptWorkflow().run(script),
  ),
];

final List<TaskHandler<Object?>> stemTasks = <TaskHandler<Object?>>[
  FunctionTaskHandler<Object?>(
    name: 'send_email',
    entrypoint: sendEmail,
  ),
];

void registerStemDefinitions({
  required WorkflowRegistry workflows,
  required TaskRegistry tasks,
}) {
  for (final flow in stemFlows) {
    workflows.register(flow.definition);
  }
  for (final script in stemScripts) {
    workflows.register(script.definition);
  }
  for (final handler in stemTasks) {
    tasks.register(handler);
  }
}
