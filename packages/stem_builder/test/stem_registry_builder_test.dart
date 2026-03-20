import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:stem_builder/stem_builder.dart';
import 'package:test/test.dart';

const stubStem = '''
library stem;

class FlowContext {}
typedef _FlowStepHandler = Future<Object?> Function(FlowContext context);

enum WorkflowStepKind { task, choice, parallel, wait, custom }

class PayloadCodec<T> {
  const PayloadCodec({required this.encode, required this.decode})
    : typeName = null;
  const PayloadCodec.map({
    required this.encode,
    required T Function(Map<String, dynamic> payload) decode,
    this.typeName,
  }) : decode = _unsupportedDecode;
  const PayloadCodec.json({
    required T Function(Map<String, dynamic> payload) decode,
    this.typeName,
  }) : encode = _unsupportedEncode,
       decode = _unsupportedDecode;
  final Object? Function(T value) encode;
  final T Function(Object? payload) decode;
  final String? typeName;

  static Object? _unsupportedEncode<T>(T value) => throw UnimplementedError();
  static T _unsupportedDecode<T>(Object? payload) => throw UnimplementedError();
}

class FlowStep {
  FlowStep({
    required this.name,
    required this.handler,
    this.autoVersion = false,
    this.valueCodec,
    this.title,
    this.kind = WorkflowStepKind.task,
    this.taskNames = const [],
    this.metadata,
  });
  final String name;
  final _FlowStepHandler handler;
  final bool autoVersion;
  final PayloadCodec<Object?>? valueCodec;
  final String? title;
  final WorkflowStepKind kind;
  final List<String> taskNames;
  final Map<String, Object?>? metadata;
}
class WorkflowCheckpoint {
  WorkflowCheckpoint({
    required this.name,
    this.autoVersion = false,
    this.valueCodec,
    this.title,
    this.kind = WorkflowStepKind.task,
    this.taskNames = const [],
    this.metadata,
  });
  final String name;
  final bool autoVersion;
  final PayloadCodec<Object?>? valueCodec;
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

class NoArgsTaskDefinition<T> {
  const NoArgsTaskDefinition({
    required this.name,
    this.defaultOptions = const TaskOptions(),
    this.metadata = const TaskMetadata(),
    this.decodeResult,
  });

  final String name;
  final TaskOptions defaultOptions;
  final TaskMetadata metadata;
  final T Function(Object? payload)? decodeResult;
}

class TaskOptions {
  const TaskOptions({this.maxRetries = 0});
  final int maxRetries;
}

class TaskMetadata {
  const TaskMetadata();
}

class WorkflowDefn {
  const WorkflowDefn({
    this.name,
    this.kind = WorkflowKind.flow,
    this.starterName,
    this.nameField,
  });
  final String? name;
  final WorkflowKind kind;
  final String? starterName;
  final String? nameField;
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
  Flow({
    required String name,
    required void Function(dynamic) build,
    PayloadCodec<T>? resultCodec,
  });
}

class WorkflowScript<T> {
  WorkflowScript({
    required String name,
    required dynamic run,
    List<WorkflowCheckpoint> checkpoints = const [],
    PayloadCodec<T>? resultCodec,
  });
}

class TaskHandler<T> {}

class FunctionTaskHandler<T> implements TaskHandler<T> {
  FunctionTaskHandler({required String name, required dynamic entrypoint});
}

class Stem {
  Future<TaskResult<T>?> waitForTaskDefinition<TArgs, T extends Object?>(
    String taskId,
    TaskDefinition<TArgs, T> definition, {
    Duration? timeout,
  }) async => null;
}

class TaskResult<T extends Object?> {
  const TaskResult();
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

part 'workflows.stem.g.dart';

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
        'stem_builder|lib/workflows.stem.g.dart': decodedMatches(
          allOf([
            contains('StemWorkflowDefinitions'),
            contains('StemTaskDefinitions'),
            contains('NoArgsWorkflowRef<String>'),
            contains('Flow('),
            contains('WorkflowScript('),
            contains('stemModule = StemModule('),
            contains('FunctionTaskHandler'),
            contains("part of 'workflows.dart';"),
            isNot(contains('StemGeneratedTaskEnqueuer')),
            isNot(contains('StemGeneratedTaskResults')),
            isNot(contains('waitForSendEmail(')),
          ]),
        ),
      },
    );
  });

  test('rejects @workflow.run without script kind', () async {
    const input = '''
import 'package:stem/stem.dart';

part 'workflows.stem.g.dart';

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
    'honors workflow starter/name field overrides from annotations',
    () async {
      const input = '''
import 'package:stem/stem.dart';

part 'workflows.stem.g.dart';

@WorkflowDefn(
  name: 'hello.flow',
  starterName: 'LaunchHello',
  nameField: 'helloFlow',
)
class HelloWorkflow {
  @WorkflowStep()
  Future<void> stepOne() async {}
}

@WorkflowDefn(
  name: 'billing.daily_sync',
  kind: WorkflowKind.script,
  starterName: 'startDailyBilling',
  nameField: 'dailyBilling',
)
class DailyBillingWorkflow {
  @WorkflowRun()
  Future<void> run(String tenant) async {}
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
          'stem_builder|lib/workflows.stem.g.dart': decodedMatches(
            allOf([
              contains(
                'static final NoArgsWorkflowRef<Object?> '
                'helloFlow =',
              ),
              contains(
                'static final WorkflowRef<String, Object?> '
                'dailyBilling =',
              ),
            ]),
          ),
        },
      );
    },
  );

  test('uses NoArgsWorkflowRef for zero-argument script workflows', () async {
    const input = '''
import 'package:stem/stem.dart';

part 'workflows.stem.g.dart';

@WorkflowDefn(kind: WorkflowKind.script)
class HelloScriptWorkflow {
  @WorkflowRun()
  Future<String> run() async => 'done';
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
        'stem_builder|lib/workflows.stem.g.dart': decodedMatches(
          allOf([
            contains(
              'static final NoArgsWorkflowRef<String> '
              'helloScriptWorkflow =',
            ),
            contains('NoArgsWorkflowRef<String>('),
            isNot(contains('startHelloScriptWorkflow(')),
            isNot(contains('startAndWaitHelloScriptWorkflow(')),
            isNot(contains('waitForHelloScriptWorkflow(')),
          ]),
        ),
      },
    );
  });

  test('uses NoArgsTaskDefinition for zero-argument tasks', () async {
    const input = '''
import 'package:stem/stem.dart';

part 'workflows.stem.g.dart';

@TaskDefn(name: 'ping.task')
Future<String> pingTask() async => 'pong';
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
        'stem_builder|lib/workflows.stem.g.dart': decodedMatches(
          allOf([
            contains('static final NoArgsTaskDefinition<String> pingTask ='),
            contains('NoArgsTaskDefinition<String>('),
            isNot(contains('enqueuePingTask(')),
            isNot(contains('enqueueAndWaitPingTask(')),
            isNot(contains('encodeArgs: (args) => const <String, Object?>{}')),
          ]),
        ),
      },
    );
  });

  test('generates direct helpers for typed annotated tasks', () async {
    const input = '''
import 'package:stem/stem.dart';

part 'workflows.stem.g.dart';

class EmailRequest {
  const EmailRequest({required this.email});
  final String email;
  Map<String, Object?> toJson() => {'email': email};
  factory EmailRequest.fromJson(Map<String, Object?> json) =>
      EmailRequest(email: json['email'] as String);
}

@TaskDefn(name: 'email.send')
Future<String> sendEmail(EmailRequest request) async => request.email;
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
        'stem_builder|lib/workflows.stem.g.dart': decodedMatches(
          allOf([
            contains(
              'static final TaskDefinition<EmailRequest, String> emailSend =',
            ),
            isNot(contains('enqueueEmailSend(')),
            isNot(contains('enqueueAndWaitEmailSend(')),
          ]),
        ),
      },
    );
  });

  test('generates direct helpers for typed workflows', () async {
    const input = '''
import 'package:stem/stem.dart';

part 'workflows.stem.g.dart';

@WorkflowDefn(kind: WorkflowKind.script)
class SignupWorkflow {
  Future<String> run(String email) async => email;
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
        'stem_builder|lib/workflows.stem.g.dart': decodedMatches(
          allOf([
            contains(
              'static final WorkflowRef<String, String> signupWorkflow =',
            ),
            isNot(contains('startSignupWorkflow(')),
            isNot(contains('startAndWaitSignupWorkflow(')),
            isNot(contains('waitForSignupWorkflow(')),
          ]),
        ),
      },
    );
  });

  test('generates typed workflow refs for annotated flows', () async {
    const input = r'''
import 'package:stem/stem.dart';

part 'workflows.stem.g.dart';

@WorkflowDefn()
class GreetingFlow {
  @WorkflowStep()
  Future<String> greet(String name) async => 'hello \$name';
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
        'stem_builder|lib/workflows.stem.g.dart': decodedMatches(
          allOf([
            contains(
              'static final WorkflowRef<String, String> greetingFlow =',
            ),
            isNot(contains('startGreetingFlow(')),
            isNot(contains('startAndWaitGreetingFlow(')),
            isNot(contains('waitForGreetingFlow(')),
          ]),
        ),
      },
    );
  });

  test(
    'generates script workflow step proxies for direct method calls',
    () async {
      const input = '''
import 'package:stem/stem.dart';

part 'workflows.stem.g.dart';

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
          'stem_builder|lib/workflows.stem.g.dart': decodedMatches(
            allOf([
              contains(
                'class _StemScriptProxy0 extends ScriptWithStepsWorkflow',
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

  test(
    'supports script workflows with plain run(...) and no @WorkflowRun',
    () async {
      const input = '''
import 'package:stem/stem.dart';

part 'workflows.stem.g.dart';

@WorkflowDefn(kind: WorkflowKind.script)
class ScriptWorkflow {
  Future<String> run(String email) async => sendEmail(email);

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
          'stem_builder|lib/workflows.stem.g.dart': decodedMatches(
            allOf([
              contains('class _StemScriptProxy0 extends ScriptWorkflow'),
              contains(
                'run: (script) => _StemScriptProxy0(',
              ),
              contains('_stemRequireArg(script.params, "email") as String'),
            ]),
          ),
        },
      );
    },
  );

  test('rejects script workflow steps that are not async', () async {
    const input = '''
import 'package:stem/stem.dart';

part 'workflows.stem.g.dart';

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

  test('rejects duplicate script checkpoint names', () async {
    const input = '''
import 'package:stem/stem.dart';

part 'workflows.stem.g.dart';

@WorkflowDefn(kind: WorkflowKind.script)
class DuplicateCheckpointWorkflow {
  Future<void> run() async {
    await first();
    await second();
  }

  @WorkflowStep(name: 'shared')
  Future<void> first() async {}

  @WorkflowStep(name: 'shared')
  Future<void> second() async {}
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
    expect(result.errors.join('\n'), contains('duplicate checkpoint names'));
    expect(result.errors.join('\n'), contains('"shared" from first, second'));
  });

  test(
    'rejects manual checkpoint names that conflict with annotated ones',
    () async {
      const input = '''
import 'package:stem/stem.dart';

part 'workflows.stem.g.dart';

@WorkflowDefn(kind: WorkflowKind.script)
class DuplicateManualCheckpointWorkflow {
  @WorkflowRun()
  Future<void> run(WorkflowScriptContext script) async {
    await script.step<void>('send-email', (ctx) => sendEmail('user@example.com'));
  }

  @WorkflowStep(name: 'send-email')
  Future<void> sendEmail(String email) async {}
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
      expect(result.errors.join('\n'), contains('manual checkpoint'));
      expect(
        result.errors.join('\n'),
        contains('conflicts with annotated checkpoint'),
      );
    },
  );

  test(
    'warns when manual script.step wraps an annotated checkpoint call',
    () async {
      const input = '''
import 'package:stem/stem.dart';

part 'workflows.stem.g.dart';

@WorkflowDefn(kind: WorkflowKind.script)
class MixedCheckpointWorkflow {
  @WorkflowRun()
  Future<void> run(WorkflowScriptContext script) async {
    await script.step<void>('outer-wrapper', (ctx) => sendEmail('user@example.com'));
  }

  @WorkflowStep(name: 'send-email')
  Future<void> sendEmail(String email) async {}
}
''';

      final records = <Object?>[];
      await testBuilders(
        [stemRegistryBuilder(BuilderOptions.empty)],
        {'stem_builder|lib/workflows.dart': input},
        rootPackage: 'stem_builder',
        onLog: records.add,
        readerWriter: TestReaderWriter(rootPackage: 'stem_builder')
          ..testing.writeString(
            AssetId('stem', 'lib/stem.dart'),
            stubStem,
          ),
      );

      expect(
        records,
        contains(
          warningLogOf(
            allOf([
              contains('wraps annotated checkpoint "send-email"'),
              contains('outer-wrapper'),
              contains('avoid nested checkpoints'),
            ]),
          ),
        ),
      );
    },
  );

  test(
    'warns when manual script.step wraps a context-aware annotated '
    'checkpoint call',
    () async {
      const input = '''
import 'package:stem/stem.dart';

part 'workflows.stem.g.dart';

@WorkflowDefn(kind: WorkflowKind.script)
class MixedContextCheckpointWorkflow {
  @WorkflowRun()
  Future<void> run(WorkflowScriptContext script) async {
    await script.step<void>(
      'outer-wrapper',
      (ctx) => capture('user@example.com', context: ctx),
    );
  }

  @WorkflowStep(name: 'capture')
  Future<void> capture(
    String email, {
    WorkflowScriptStepContext? context,
  }) async {}
}
''';

      final records = <Object?>[];
      await testBuilders(
        [stemRegistryBuilder(BuilderOptions.empty)],
        {'stem_builder|lib/workflows.dart': input},
        rootPackage: 'stem_builder',
        onLog: records.add,
        readerWriter: TestReaderWriter(rootPackage: 'stem_builder')
          ..testing.writeString(
            AssetId('stem', 'lib/stem.dart'),
            stubStem,
          ),
      );

      expect(
        records,
        contains(
          warningLogOf(
            allOf([
              contains('wraps annotated checkpoint "capture"'),
              contains('outer-wrapper'),
              contains('avoid nested checkpoints'),
            ]),
          ),
        ),
      );
    },
  );

  test(
    'decodes serializable @workflow.run parameters from script params',
    () async {
      const input = '''
import 'package:stem/stem.dart';

part 'workflows.stem.g.dart';

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
          'stem_builder|lib/workflows.stem.g.dart': decodedMatches(
            allOf([
              contains(
                'run: (script) => _StemScriptProxy0(',
              ),
              contains(
                ').run((_stemRequireArg(script.params, "email") as String))',
              ),
              contains('_stemRequireArg(script.params, "email") as String'),
              contains('abstract final class StemWorkflowDefinitions'),
              contains(
                'static final WorkflowRef<String, Map<String, Object?>> '
                'signupWorkflow =',
              ),
              isNot(contains('extraParams')),
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

part 'workflows.stem.g.dart';

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
          'stem_builder|lib/workflows.stem.g.dart': decodedMatches(
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

  test(
    'supports optional named WorkflowScriptContext injection',
    () async {
      const input = '''
import 'package:stem/stem.dart';

part 'workflows.stem.g.dart';

@WorkflowDefn(kind: WorkflowKind.script)
class SignupWorkflow {
  Future<void> run(String email, {WorkflowScriptContext? context}) async {
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
          'stem_builder|lib/workflows.stem.g.dart': decodedMatches(
            allOf([
              contains(
                ').run(('
                '_stemRequireArg(script.params, "email") as String), '
                'context: script)',
              ),
            ]),
          ),
        },
      );
    },
  );

  test(
    'supports optional named WorkflowScriptStepContext injection',
    () async {
      const input = '''
import 'package:stem/stem.dart';

part 'workflows.stem.g.dart';

@WorkflowDefn(kind: WorkflowKind.script)
class SignupWorkflow {
  Future<String> run(String email) async => sendWelcomeEmail(email);

  @WorkflowStep()
  Future<String> sendWelcomeEmail(
    String email, {
    WorkflowScriptStepContext? context,
  }) async => email;
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
          'stem_builder|lib/workflows.stem.g.dart': decodedMatches(
            allOf([
              contains(
                '(context) => super.sendWelcomeEmail(email, context: context)',
              ),
              contains('WorkflowScriptStepContext? context'),
            ]),
          ),
        },
      );
    },
  );

  test('supports optional named FlowContext injection', () async {
    const input = '''
import 'package:stem/stem.dart';

part 'workflows.stem.g.dart';

@WorkflowDefn(name: 'hello.flow')
class HelloWorkflow {
  @WorkflowStep(name: 'step-1')
  Future<String> stepOne({FlowContext? context}) async => 'ok';
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
        'stem_builder|lib/workflows.stem.g.dart': decodedMatches(
          contains('(ctx) => impl.stepOne(context: ctx)'),
        ),
      },
    );
  });

  test('supports optional named TaskInvocationContext injection', () async {
    const input = '''
import 'package:stem/stem.dart';

part 'workflows.stem.g.dart';

@TaskDefn(name: 'typed.task')
Future<void> typedTask(
  String email, {
  TaskInvocationContext? context,
}) async {}
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
        'stem_builder|lib/workflows.stem.g.dart': decodedMatches(
          allOf([
            contains('typedTask((_stemRequireArg(args, "email") as String),'),
            contains('context: context'),
          ]),
        ),
      },
    );
  });

  test('rejects non-serializable @workflow.run parameter types', () async {
    const input = '''
import 'package:stem/stem.dart';

part 'workflows.stem.g.dart';

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
    expect(
      result.errors.join('\n'),
      contains('serializable or codec-backed DTO type'),
    );
  });

  test('rejects task args that are not Map<String, Object?>', () async {
    const input = '''
import 'package:stem/stem.dart';

part 'workflows.stem.g.dart';

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
    expect(
      result.errors.join('\n'),
      contains('serializable or codec-backed DTO type'),
    );
  });

  test('generates adapters for typed workflow and task parameters', () async {
    const input = '''
import 'package:stem/stem.dart';

part 'workflows.stem.g.dart';

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
        'stem_builder|lib/workflows.stem.g.dart': decodedMatches(
          allOf([
            contains('_stemRequireArg(ctx.params, "email") as String'),
            contains('_stemRequireArg(ctx.params, "retries") as int'),
            contains('Future<Object?> _stemTaskAdapter0('),
            contains('_stemRequireArg(args, "email") as String'),
            contains('_stemRequireArg(args, "retries") as int'),
            contains('entrypoint: _stemTaskAdapter0'),
          ]),
        ),
      },
    );
  });

  test(
    'generates codec-backed DTO helpers for workflow and task types',
    () async {
      const input = '''
import 'package:stem/stem.dart';

part 'workflows.stem.g.dart';

class EmailRequest {
  const EmailRequest({required this.email, required this.retries});

  final String email;
  final int retries;

  Map<String, Object?> toJson() => {
    'email': email,
    'retries': retries,
  };

  factory EmailRequest.fromJson(Map<String, dynamic> json) => EmailRequest(
    email: json['email'] as String,
    retries: json['retries'] as int,
  );
}

@WorkflowDefn(name: 'dto.script', kind: WorkflowKind.script)
class DtoWorkflow {
  Future<EmailRequest> run(EmailRequest request) async => send(request);

  @WorkflowStep(name: 'send')
  Future<EmailRequest> send(EmailRequest request) async => request;
}

@TaskDefn(name: 'dto.task')
Future<EmailRequest> dtoTask(
  TaskInvocationContext context,
  EmailRequest request,
) async => request;
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
          'stem_builder|lib/workflows.stem.g.dart': decodedMatches(
            allOf([
              contains('abstract final class StemPayloadCodecs'),
              contains('PayloadCodec<EmailRequest> emailRequest ='),
              contains('PayloadCodec<EmailRequest>.json('),
              contains(
                'WorkflowRef<EmailRequest, EmailRequest> script =',
              ),
              contains('decode: EmailRequest.fromJson,'),
              contains('typeName: "EmailRequest",'),
              contains(
                'StemPayloadCodecs.emailRequest.encode(params)',
              ),
              contains('StemPayloadCodecs.emailRequest.decode('),
              contains(
                '_stemRequireArg(script.params, "request"),',
              ),
              contains(
                'StemPayloadCodecs.emailRequest.decode('
                '_stemRequireArg(args, "request"))',
              ),
              contains('decodeResult: StemPayloadCodecs.emailRequest.decode,'),
              contains('CodecTaskPayloadEncoder<EmailRequest>('),
              contains('valueCodec: StemPayloadCodecs.emailRequest,'),
              contains('resultCodec: StemPayloadCodecs.emailRequest,'),
            ]),
          ),
        },
      );
    },
  );

  test('rejects non-serializable workflow step parameter types', () async {
    const input = '''
import 'package:stem/stem.dart';

part 'workflows.stem.g.dart';

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
    expect(
      result.errors.join('\n'),
      contains('serializable or codec-backed DTO type'),
    );
  });
}
