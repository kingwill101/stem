import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const _fixtureBasename = r'fixture$quoted';

/// This test deliberately does not use `build_test`'s in-memory asset reader.
/// It is a small consumer package: the real analyzer sees the real `stem`
/// package and build_runner invokes the real builder.
void main() {
  test(
    'generates, analyzes, and runs a real Stem consumer',
    () async {
      final root = await Directory.systemTemp.createTemp('stem-builder-');
      addTearDown(() => root.delete(recursive: true));

      final repo = _repositoryRoot();
      await _writeFixture(root, repo);

      await _run(root, 'pub', ['get', '--offline']);
      // Cold bootstrap includes AOT compilation of the analyzer-backed builder.
      await _run(
        root,
        'run',
        ['build_runner', 'build', '--delete-conflicting-outputs'],
        processTimeout: const Duration(minutes: 3),
      );
      final generated = File(
        '${root.path}/lib/$_fixtureBasename.stem.g.dart',
      );
      expect(generated.existsSync(), isTrue);
      final first = await generated.readAsString();

      // Invalidate the source asset so this checks emission again, not merely
      // an unchanged build cache preserving the old generated file.
      await File(
        '${root.path}/lib/$_fixtureBasename.dart',
      ).writeAsString('$_fixtureSource\n');
      await _run(root, 'run', [
        'build_runner',
        'build',
        '--delete-conflicting-outputs',
      ]);
      expect(await generated.readAsString(), first);

      await _run(root, 'analyze', ['lib', 'bin']);
      final result = await _run(root, 'run', ['bin/main.dart']);
      expect(result.stdout, contains('fixture-ok'));
      expect(result.stdout, contains('sync=7'));
      expect(result.stdout, contains('void=void'));
      expect(result.stdout, contains('list=[1, 2, 3]'));
      expect(result.stdout, contains('map={one: 1, two: 2}'));
      expect(result.stdout, contains('dto=Ada'));
      expect(result.stdout, contains('custom=Grace'));
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

String _repositoryRoot() {
  // Tests run from packages/stem_builder, while a checkout may itself be
  // elsewhere. Walking upward makes this work from `dart test` and editors.
  var directory = Directory.current;
  while (directory.parent.path != directory.path) {
    if (File('${directory.path}/pubspec.yaml').existsSync() &&
        Directory('${directory.path}/packages/stem').existsSync()) {
      return directory.path;
    }
    directory = directory.parent;
  }
  throw StateError('Could not locate the Stem checkout');
}

Future<void> _writeFixture(Directory root, String repo) async {
  await Directory('${root.path}/lib').create(recursive: true);
  await Directory('${root.path}/bin').create(recursive: true);
  await File('${root.path}/pubspec.yaml').writeAsString('''
name: compiler_fixture
publish_to: none
environment:
  sdk: ">=3.13.0 <4.0.0"
dependencies:
  stem:
    path: ${jsonEncode('$repo/packages/stem')}
dev_dependencies:
  stem_builder:
    path: ${jsonEncode('$repo/packages/stem_builder')}
  build_runner: ^2.10.5
dependency_overrides:
  stem:
    path: ${jsonEncode('$repo/packages/stem')}
''');
  await File('${root.path}/build.yaml').writeAsString(r'''
targets:
  $default:
    builders:
      stem_builder:stem_registry_builder:
        generate_for:
          - lib/**.dart
''');
  await File(
    '${root.path}/lib/$_fixtureBasename.dart',
  ).writeAsString(_fixtureSource);
  await File('${root.path}/bin/main.dart').writeAsString(_mainSource);
}

Future<ProcessResult> _run(
  Directory directory,
  String executable,
  List<String> arguments, {
  Duration processTimeout = const Duration(seconds: 90),
}) async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    [executable, ...arguments],
    workingDirectory: directory.path,
  );
  final output = StringBuffer();
  final errors = StringBuffer();
  final stdout = process.stdout.transform(utf8.decoder).listen(output.write);
  final stderr = process.stderr.transform(utf8.decoder).listen(errors.write);
  final drained = Future.wait<void>([stdout.asFuture(), stderr.asFuture()]);
  try {
    final completion = await Future.wait<Object?>([
      process.exitCode,
      drained,
    ]).timeout(processTimeout);
    final exitCode = completion.first! as int;
    final result = ProcessResult(
      process.pid,
      exitCode,
      output.toString(),
      errors.toString(),
    );
    if (exitCode != 0) {
      fail(
        'dart $executable ${arguments.join(' ')} failed ($exitCode)\n'
        '${result.stdout}\n${result.stderr}',
      );
    }
    return result;
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    fail(
      'dart $executable ${arguments.join(' ')} exceeded its process/output deadline\n'
      '$output\n$errors',
    );
  } finally {
    await stdout.cancel();
    await stderr.cancel();
  }
}

const _fixtureSource = r'''
import 'dart:async';
import 'dart:convert';

import 'package:stem/stem.dart';

part r'fixture$quoted.stem.g.dart';

class const Person(final String name) {
  Map<String, Object?> toJson() => {'name': name};
  factory Person.fromJson(Map<String, Object?> json) =>
      Person(json['name']! as String);
}

class PersonCodec extends Codec<Person, Object?> {
  const PersonCodec();

  @override
  Converter<Person, Object?> get encoder => const _PersonEncoder();
  @override
  Converter<Object?, Person> get decoder => const _PersonDecoder();
  @override
  Object? encode(Person input) => input.toJson();
  @override
  Person decode(Object? encoded) =>
      Person.fromJson(encoded! as Map<String, Object?>);
}

class _PersonEncoder extends Converter<Person, Object?> {
  const _PersonEncoder();
  @override
  Object? convert(Person input) => input.toJson();
}

class _PersonDecoder extends Converter<Object?, Person> {
  const _PersonDecoder();
  @override
  Person convert(Object? input) =>
      Person.fromJson(input! as Map<String, Object?>);
}

class PeopleCodec extends Codec<List<Person>, Object?> {
  const PeopleCodec();
  @override
  Converter<List<Person>, Object?> get encoder => const _PeopleEncoder();
  @override
  Converter<Object?, List<Person>> get decoder => const _PeopleDecoder();
  @override
  Object? encode(List<Person> input) =>
      input.map((person) => person.toJson()).toList();
  @override
  List<Person> decode(Object? encoded) => (encoded! as List<Object?>)
      .map((item) => Person.fromJson(item! as Map<String, Object?>))
      .toList();
}

class _PeopleEncoder extends Converter<List<Person>, Object?> {
  const _PeopleEncoder();
  @override
  Object? convert(List<Person> input) =>
      input.map((person) => person.toJson()).toList();
}

class _PeopleDecoder extends Converter<Object?, List<Person>> {
  const _PeopleDecoder();
  @override
  List<Person> convert(Object? input) => (input! as List<Object?>)
      .map((item) => Person.fromJson(item! as Map<String, Object?>))
      .toList();
}

int personCodecGetterEvaluations = 0;

@PayloadCodecDefn()
Codec<Person, Object?> get personCodec {
  personCodecGetterEvaluations++;
  return const PersonCodec();
}

@PayloadCodecDefn()
Codec<List<Person>, Object?> get peopleCodec => const PeopleCodec();

class const Box<T>(final T value);

class IntBoxCodec extends Codec<Box<int>, Object?> {
  const IntBoxCodec();
  @override
  Converter<Box<int>, Object?> get encoder => const _IntBoxEncoder();
  @override
  Converter<Object?, Box<int>> get decoder => const _IntBoxDecoder();
}

class _IntBoxEncoder extends Converter<Box<int>, Object?> {
  const _IntBoxEncoder();
  @override
  Object? convert(Box<int> input) => {'value': input.value};
}

class _IntBoxDecoder extends Converter<Object?, Box<int>> {
  const _IntBoxDecoder();
  @override
  Box<int> convert(Object? input) =>
      Box((input! as Map<String, Object?>)['value']! as int);
}

@PayloadCodecDefn()
const IntBoxCodec boxInt = IntBoxCodec();

@WorkflowDefn(
  name: r'compiler.$flow',
  nameField: 'collectionFlow',
  metadata: const {'price': r'$5', 'quote': r'keep $ literal'},
)
class CompilerFlow {
  @WorkflowStep(name: r'sync-$step')
  int primitive() => 7;

  @WorkflowStep(name: r'void-$step')
  void voidStep() {}

  @WorkflowStep(name: r'list-$step')
  List<int> list() => [1, 2, 3];

  @WorkflowStep(name: r'map-$step')
  Map<String, int> map() => {'one': 1, 'two': 2};
}

@WorkflowDefn(name: 'compiler.compatible', nameField: 'compatibleInputs')
class CompatibleFlow {
  @WorkflowStep()
  void first(int count, String label) {}

  @WorkflowStep()
  String later(num count, String? label) => '$count:$label';
}

@WorkflowDefn(name: 'compiler.dto', kind: WorkflowKind.script)
class DtoFlow {
  @WorkflowRun()
  Future<Person?> run(Person? person) async => checkpoint(person);

  @WorkflowStep()
  Future<Person?> checkpoint(Person? person) async => person;
}

@WorkflowDefn(name: 'compiler.custom-dto', kind: WorkflowKind.script)
class CustomDtoFlow {
  @WorkflowRun()
  Future<Person> run(Person person) async => checkpoint(person);

  @WorkflowStep()
  Future<Person> checkpoint(Person person) async => person;
}

int replayCheckpointExecutions = 0;
bool _retryReplayOnce = true;

@WorkflowDefn(
  name: 'compiler.replay',
  nameField: 'replayWorkflow',
  kind: WorkflowKind.script,
)
class ReplayFlow {
  @WorkflowRun()
  Future<String> run() async {
    final saved = await checkpoint();
    if (_retryReplayOnce) {
      _retryReplayOnce = false;
      throw TaskRetryRequest(countdown: Duration.zero, maxRetries: 1);
    }
    return saved;
  }

  @WorkflowStep()
  Future<String> checkpoint() async {
    replayCheckpointExecutions++;
    return 'cached';
  }
}

@TaskDefn(name: r'compiler.sync-$task', runInIsolate: false)
int syncTask() => 7;

@TaskDefn(name: r'compiler.void-$task', runInIsolate: true)
Future<void> voidTask() async {}

@TaskDefn(name: 'compiler.sync-void', runInIsolate: false)
void syncVoidTask() {}

@TaskDefn(name: 'compiler.future-or-void', runInIsolate: false)
FutureOr<void> futureOrVoidTask() {}

@TaskDefn(name: r'compiler.list-$task', runInIsolate: false)
Future<List<int>> listTask() async => [1, 2, 3];

@TaskDefn(name: r'compiler.map-$task', runInIsolate: true)
FutureOr<Map<String, int>> mapTask() => {'one': 1, 'two': 2};

@TaskDefn(name: 'compiler.nested')
Future<List<Map<String, int>>> nestedTask() async => [
  {'one': 1},
];

@TaskDefn(name: 'compiler.people')
Future<List<Person>> peopleTask() async => [Person('Grace')];

@TaskDefn(name: 'compiler.box', runInIsolate: false)
Future<Box<int>> boxTask(Box<int> value) async => Box(value.value + 1);
''';

const _mainSource = r'''
import r'package:compiler_fixture/fixture$quoted.dart';
import 'package:stem/stem.dart';

Future<void> main() async {
  final app = await StemApp.inMemory(module: stemModule);
  final workflowApp = await StemWorkflowApp.inMemory(module: stemModule);
  try {
    await app.start();
    await workflowApp.start();
    final sync = await StemTaskDefinitions.compilerSyncTask.enqueueAndWait(
      app,
      timeout: const Duration(seconds: 5),
    );
    final voidResult = await StemTaskDefinitions.compilerVoidTask.enqueueAndWait(
      app,
      timeout: const Duration(seconds: 5),
    );
    final syncVoidResult = await StemTaskDefinitions.compilerSyncVoid.enqueueAndWait(
      app,
      timeout: const Duration(seconds: 5),
    );
    final futureOrVoidResult = await StemTaskDefinitions.compilerFutureOrVoid.enqueueAndWait(
      app,
      timeout: const Duration(seconds: 5),
    );
    final list = await StemTaskDefinitions.compilerListTask.enqueueAndWait(
      app,
      timeout: const Duration(seconds: 5),
    );
    final map = await StemTaskDefinitions.compilerMapTask.enqueueAndWait(
      app,
      timeout: const Duration(seconds: 5),
    );
    final nested = await StemTaskDefinitions.compilerNested.enqueueAndWait(
      app,
      timeout: const Duration(seconds: 5),
    );
    final people = await StemTaskDefinitions.compilerPeople.enqueueAndWait(
      app,
      timeout: const Duration(seconds: 5),
    );
    final box = await StemTaskDefinitions.compilerBox.enqueueAndWait(
      app,
      const Box(41),
      timeout: const Duration(seconds: 5),
    );
    final dto = Person('Ada');
    final dtoResult = await StemWorkflowDefinitions.dto.startAndWait(
      workflowApp,
      params: dto,
      timeout: const Duration(seconds: 5),
    );
    final customDtoResult =
        await StemWorkflowDefinitions.customDto.startAndWait(
      workflowApp,
      params: Person('Grace'),
      timeout: const Duration(seconds: 5),
    );
    final nullDto = await StemWorkflowDefinitions.dto.startAndWait(
      workflowApp,
      params: null,
      timeout: const Duration(seconds: 5),
    );
    final flow = await StemWorkflowDefinitions.collectionFlow.startAndWait(
      workflowApp,
      timeout: const Duration(seconds: 5),
    );
    final replay = await StemWorkflowDefinitions.replayWorkflow.startAndWait(
      workflowApp,
      timeout: const Duration(seconds: 5),
    );
    final compatible = await StemWorkflowDefinitions.compatibleInputs.startAndWait(
      workflowApp,
      params: (count: 3, label: 'safe'),
      timeout: const Duration(seconds: 5),
    );
    if ([sync, voidResult, syncVoidResult, futureOrVoidResult, list, map, nested, people].any((r) => r?.isSucceeded != true) ||
        sync?.value != 7 ||
        voidResult?.value != null ||
        list?.value.toString() != '[1, 2, 3]' ||
        map?.value?['one'] != 1 ||
        map?.value?['two'] != 2 ||
        nested?.value?.single['one'] != 1 ||
        people?.value?.single.name != 'Grace' ||
        box?.value?.value != 42 ||
        dtoResult?.value?.name != 'Ada' ||
        customDtoResult?.value?.name != 'Grace' ||
        nullDto?.status != WorkflowStatus.completed ||
        nullDto?.value != null ||
        personCodecGetterEvaluations != 1 ||
        flow?.value?['two'] != 2 ||
        replay?.value != 'cached' ||
        replayCheckpointExecutions != 1 ||
        compatible?.value != '3:safe' ||
        StemTaskDefinitions.compilerSyncTask.name != r'compiler.sync-$task' ||
        StemWorkflowDefinitions.collectionFlow.name != r'compiler.$flow' ||
        stemModule.workflowManifest
            .firstWhere((entry) => entry.name == r'compiler.$flow')
            .metadata?['quote'] != r'keep $ literal') {
      throw StateError(
        'generated runtime values were not preserved: '
        'sync=${sync?.value}, void=${voidResult?.status.state}, '
        'list=${list?.value}, map=${map?.value}, nested=${nested?.value}, '
        'dto=${dtoResult?.value?.name}, nullDto=${nullDto?.status}, flow=${flow?.value}',
      );
    }
    print('fixture-ok sync=${sync?.value} void=void list=${list?.value} '
        'map=${map?.value} nested=${nested?.value} dto=${dtoResult?.value?.name} '
        'custom=${customDtoResult?.value?.name}');
  } finally {
    await workflowApp.close();
    await app.shutdown();
  }
}
''';
