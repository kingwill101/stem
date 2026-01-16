import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:stem_builder/stem_builder.dart';
import 'package:test/test.dart';

void main() {
  test('generates workflow and task registry', () async {
    const stubStem = '''
library stem;

class FlowContext {}
class WorkflowScriptContext {}
class TaskInvocationContext {}

class TaskOptions {
  const TaskOptions({this.maxRetries = 0});
  final int maxRetries;
}

class TaskMetadata {
  const TaskMetadata();
}

class WorkflowDefn {
  const WorkflowDefn({this.name, this.kind = WorkflowKind.flow});
  final String? name;
  final WorkflowKind kind;
}

class WorkflowRun {
  const WorkflowRun();
}

class WorkflowStep {
  const WorkflowStep({this.name});
  final String? name;
}

class TaskDefn {
  const TaskDefn({this.name, this.options = const TaskOptions()});
  final String? name;
  final TaskOptions options;
}

enum WorkflowKind { flow, script }

class WorkflowAnnotations {
  const WorkflowAnnotations();
  final WorkflowDefn defn = const WorkflowDefn();
  final WorkflowRun run = const WorkflowRun();
  final WorkflowStep step = const WorkflowStep();
}

const workflow = WorkflowAnnotations();

class Flow<T> {
  Flow({required String name, required void Function(dynamic) build});
}

class WorkflowScript<T> {
  WorkflowScript({required String name, required dynamic run});
}

class TaskHandler<T> {}

class FunctionTaskHandler<T> implements TaskHandler<T> {
  FunctionTaskHandler({required String name, required dynamic entrypoint});
}

abstract class WorkflowRegistry {
  void register(dynamic definition);
}

abstract class TaskRegistry {
  void register(TaskHandler<Object?> handler);
}
''';

    const input = '''
import 'package:stem/stem.dart';

@WorkflowDefn(name: 'hello.flow')
class HelloWorkflow {
  @WorkflowStep(name: 'step-1')
  Future<String> stepOne(FlowContext ctx) async => 'ok';
}

@WorkflowDefn(name: 'script.workflow', kind: WorkflowKind.script)
class ScriptWorkflow {
  @WorkflowRun()
  Future<String> run(WorkflowScriptContext script) async => 'done';
}

@TaskDefn(name: 'send_email', options: TaskOptions(maxRetries: 1))
Future<void> sendEmail(
  TaskInvocationContext ctx,
  Map<String, Object?> args,
) async {}
''';

    await testBuilder(
      stemRegistryBuilder(BuilderOptions.empty),
      {'stem_builder|lib/workflows.dart': input},
      rootPackage: 'stem_builder',
      readerWriter: TestReaderWriter(rootPackage: 'stem_builder')
        ..testing.writeString(
          AssetId('stem', 'lib/stem.dart'),
          stubStem,
        ),
      outputs: {
        'stem_builder|lib/stem_registry.g.dart': decodedMatches(
          allOf([
            contains('registerStemDefinitions'),
            contains('Flow('),
            contains('WorkflowScript('),
            contains('FunctionTaskHandler'),
          ]),
        ),
      },
    );
  });
}
