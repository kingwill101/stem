import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:stem_builder/stem_builder.dart';
import 'package:test/test.dart';

const stubStem = '''
library stem;

class FlowContext {}
typedef _FlowStepHandler = Future<Object?> Function(FlowContext context);

enum WorkflowStepKind { task, choice, parallel, wait, custom }

class FlowStep {
  FlowStep({
    required this.name,
    required this.handler,
    this.autoVersion = false,
    this.title,
    this.kind = WorkflowStepKind.task,
    this.taskNames = const [],
    this.metadata,
  });
  final String name;
  final _FlowStepHandler handler;
  final bool autoVersion;
  final String? title;
  final WorkflowStepKind kind;
  final List<String> taskNames;
  final Map<String, Object?>? metadata;
}
class WorkflowScriptContext {
  Future<T> step<T>(
    String name,
    dynamic handler, {
    bool autoVersion = false,
  }) async => throw UnimplementedError();
}
class WorkflowScriptStepContext {}
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
  WorkflowScript({
    required String name,
    required dynamic run,
    List<FlowStep> steps = const [],
  });
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

void main() {
  test('generates workflow and task registry', () async {
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
            contains('StemWorkflowNames'),
            contains('StemGeneratedWorkflowAppStarters'),
            contains('StemGeneratedWorkflowRuntimeStarters'),
            contains('startHelloFlow'),
            contains('startScriptWorkflow'),
            contains('createStemGeneratedWorkflowApp'),
            contains('createStemGeneratedInMemoryApp'),
            contains('Flow('),
            contains('WorkflowScript('),
            contains('stemWorkflowManifest'),
            contains('FunctionTaskHandler'),
            contains(
              "import 'package:stem_builder/workflows.dart' as stemLib0;",
            ),
          ]),
        ),
      },
    );
  });

  test('rejects @workflow.run without script kind', () async {
    const input = '''
import 'package:stem/stem.dart';

@WorkflowDefn()
class BadWorkflow {
  @WorkflowRun()
  Future<String> run(WorkflowScriptContext script) async => 'done';
}
''';

    final result = await testBuilder(
      stemRegistryBuilder(BuilderOptions.empty),
      {'stem_builder|lib/workflows.dart': input},
      rootPackage: 'stem_builder',
      readerWriter: TestReaderWriter(rootPackage: 'stem_builder')
        ..testing.writeString(
          AssetId('stem', 'lib/stem.dart'),
          stubStem,
        ),
    );
    expect(result.succeeded, isFalse);
    expect(result.errors.join('\n'), contains('@workflow.run'));
  });

  test(
    'generates script workflow step proxies for direct method calls',
    () async {
      const input = '''
import 'package:stem/stem.dart';

@WorkflowDefn(kind: WorkflowKind.script)
class ScriptWithStepsWorkflow {
  @WorkflowRun()
  Future<String> run(WorkflowScriptContext script) async {
    return sendEmail('user@example.com');
  }

  @WorkflowStep()
  Future<String> sendEmail(String email) async => email;
}
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
              contains(
                'class _StemScriptProxy0 extends '
                'stemLib0.ScriptWithStepsWorkflow',
              ),
              contains('return _script.step<String>('),
              contains('(context) => super.sendEmail(email)'),
              contains(
                'run: (script) => _StemScriptProxy0(script).run(script)',
              ),
            ]),
          ),
        },
      );
    },
  );

  test('rejects script workflow steps that are not async', () async {
    const input = '''
import 'package:stem/stem.dart';

@WorkflowDefn(kind: WorkflowKind.script)
class BadScriptWorkflow {
  @WorkflowRun()
  Future<String> run(WorkflowScriptContext script) async {
    return sendEmail('user@example.com');
  }

  @WorkflowStep()
  String sendEmail(String email) => email;
}
''';

    final result = await testBuilder(
      stemRegistryBuilder(BuilderOptions.empty),
      {'stem_builder|lib/workflows.dart': input},
      rootPackage: 'stem_builder',
      readerWriter: TestReaderWriter(rootPackage: 'stem_builder')
        ..testing.writeString(
          AssetId('stem', 'lib/stem.dart'),
          stubStem,
        ),
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('must return Future<T> or FutureOr<T>'),
    );
  });

  test(
    'decodes serializable @workflow.run parameters from script params',
    () async {
      const input = '''
import 'package:stem/stem.dart';

@WorkflowDefn(kind: WorkflowKind.script)
class SignupWorkflow {
  @WorkflowRun()
  Future<Map<String, Object?>> run(String email) async {
    await sendWelcomeEmail(email);
    return {'email': email};
  }

  @WorkflowStep()
  Future<void> sendWelcomeEmail(String email) async {}
}
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
              contains(
                'run: (script) => _StemScriptProxy0(',
              ),
              contains(
                ').run((_stemRequireArg(script.params, "email") as String))',
              ),
              contains('_stemRequireArg(script.params, "email") as String'),
              contains('Future<String> startSignupWorkflow({'),
              contains('required String email,'),
              contains('Map<String, Object?> extraParams = const {},'),
            ]),
          ),
        },
      );
    },
  );

  test(
    'supports @workflow.run with WorkflowScriptContext plus typed parameters',
    () async {
      const input = '''
import 'package:stem/stem.dart';

@WorkflowDefn(kind: WorkflowKind.script)
class SignupWorkflow {
  @WorkflowRun()
  Future<void> run(WorkflowScriptContext script, String email) async {
    await sendWelcomeEmail(email);
  }

  @WorkflowStep()
  Future<void> sendWelcomeEmail(String email) async {}
}
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
              contains('run: (script) => _StemScriptProxy0('),
              contains(
                ').run(script, (_stemRequireArg(script.params, "email") as '
                'String))',
              ),
            ]),
          ),
        },
      );
    },
  );

  test('rejects non-serializable @workflow.run parameter types', () async {
    const input = '''
import 'package:stem/stem.dart';

@WorkflowDefn(kind: WorkflowKind.script)
class BadScriptWorkflow {
  @WorkflowRun()
  Future<void> run(DateTime when) async {}
}
''';

    final result = await testBuilder(
      stemRegistryBuilder(BuilderOptions.empty),
      {'stem_builder|lib/workflows.dart': input},
      rootPackage: 'stem_builder',
      readerWriter: TestReaderWriter(rootPackage: 'stem_builder')
        ..testing.writeString(
          AssetId('stem', 'lib/stem.dart'),
          stubStem,
        ),
    );
    expect(result.succeeded, isFalse);
    expect(result.errors.join('\n'), contains('serializable type'));
  });

  test('rejects task args that are not Map<String, Object?>', () async {
    const input = '''
import 'package:stem/stem.dart';

@TaskDefn()
Future<void> badTask(
  TaskInvocationContext ctx,
  Map<String, dynamic> args,
) async {}
''';

    final result = await testBuilder(
      stemRegistryBuilder(BuilderOptions.empty),
      {'stem_builder|lib/workflows.dart': input},
      rootPackage: 'stem_builder',
      readerWriter: TestReaderWriter(rootPackage: 'stem_builder')
        ..testing.writeString(
          AssetId('stem', 'lib/stem.dart'),
          stubStem,
        ),
    );
    expect(result.succeeded, isFalse);
    expect(result.errors.join('\n'), contains('serializable type'));
  });

  test('generates adapters for typed workflow and task parameters', () async {
    const input = '''
import 'package:stem/stem.dart';

@WorkflowDefn(name: 'typed.flow')
class TypedWorkflow {
  @WorkflowStep(name: 'send-email')
  Future<void> sendEmail(String email, int retries) async {}
}

@TaskDefn(name: 'typed.task')
Future<void> typedTask(
  TaskInvocationContext context,
  String email,
  int retries,
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
            contains('_stemRequireArg(ctx.params, "email") as String'),
            contains('_stemRequireArg(ctx.params, "retries") as int'),
            contains('FutureOr<Object?> _stemTaskAdapter0('),
            contains('_stemRequireArg(args, "email") as String'),
            contains('_stemRequireArg(args, "retries") as int'),
            contains('entrypoint: _stemTaskAdapter0'),
          ]),
        ),
      },
    );
  });

  test('rejects non-serializable workflow step parameter types', () async {
    const input = '''
import 'package:stem/stem.dart';

@WorkflowDefn(name: 'bad.flow')
class BadWorkflow {
  @WorkflowStep()
  Future<void> bad(DateTime when) async {}
}
''';

    final result = await testBuilder(
      stemRegistryBuilder(BuilderOptions.empty),
      {'stem_builder|lib/workflows.dart': input},
      rootPackage: 'stem_builder',
      readerWriter: TestReaderWriter(rootPackage: 'stem_builder')
        ..testing.writeString(
          AssetId('stem', 'lib/stem.dart'),
          stubStem,
        ),
    );

    expect(result.succeeded, isFalse);
    expect(result.errors.join('\n'), contains('serializable type'));
  });
}
