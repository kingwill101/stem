import 'dart:io';

import 'package:artisanal/args.dart';

import '../infrastructure/process_runner.dart';
import '../infrastructure/toolchain.dart';
import '../infrastructure/workspace.dart';

enum TestTarget {
  integration,
  noEnvironment,
  flutter,
  all,
  contract,
  redis,
  postgres,
}

final class TestCommand extends Command<int> {
  TestCommand(this.target);

  final TestTarget target;

  @override
  String get name => switch (target) {
    TestTarget.integration => 'test',
    TestTarget.noEnvironment => 'test:no-env',
    TestTarget.flutter => 'test:flutter',
    TestTarget.all => 'test:all',
    TestTarget.contract => 'test:contract',
    TestTarget.redis => 'test:redis',
    TestTarget.postgres => 'test:postgres',
  };

  @override
  String get description => switch (target) {
    TestTarget.integration =>
      'Run all Dart package tests with integration services bootstrapped.',
    TestTarget.noEnvironment =>
      'Run all non-Flutter package tests without bootstrapping services.',
    TestTarget.flutter => 'Analyze and test the Flutter packages.',
    TestTarget.all => 'Run the complete Dart and Flutter test gate.',
    TestTarget.contract => 'Run adapter contract-heavy test suites.',
    TestTarget.redis => 'Run the Redis adapter tests.',
    TestTarget.postgres => 'Run the PostgreSQL adapter tests.',
  };

  @override
  Future<int> run() async {
    final catalog = WorkspaceCatalog.load();
    final orchestrator = TestOrchestrator(catalog);
    await orchestrator.run(target);
    return 0;
  }
}

final class PackageTestCommand extends Command<int> {
  PackageTestCommand() {
    argParser
      ..addOption('package', help: 'Package path to test.')
      ..addFlag(
        'multi',
        help: 'Enable the stem_cli multi-worker test coverage path.',
        negatable: false,
      );
  }

  @override
  String get name => 'test:package';

  @override
  String get description => 'Run the tests for one Dart package.';

  @override
  Future<int> run() async {
    final path = argResults?['package'] as String?;
    if (path == null || path.isEmpty) {
      throw ArgumentError('Missing required option: --package');
    }
    final catalog = WorkspaceCatalog.load();
    final matches = catalog.select(
      requestedPaths: [path],
      includeFlutter: true,
    );
    if (matches.length != 1 || matches.single.isFlutter) {
      throw ArgumentError('Expected one Dart package at $path.');
    }
    var environment = Platform.environment.containsKey('STEM_CLI_RUN_MULTI')
        ? Map<String, String>.from(Platform.environment)
        : null;
    if (argResults?['multi'] == true) {
      (environment ??= Map<String, String>.from(
        Platform.environment,
      ))['STEM_CLI_RUN_MULTI'] = 'true';
    }
    final resolvedEnvironment = await TestOrchestrator(
      catalog,
    ).resolveDependencies(environment: environment);
    await ProcessRunner(environment: catalog.processEnvironment).run(
      'dart',
      ['test', '--fail-fast'],
      workingDirectory: matches.single.directory,
      environment: resolvedEnvironment,
      label: 'test $path',
    );
    return 0;
  }
}

final class TestOrchestrator {
  TestOrchestrator(this.catalog, {ProcessRunner? runner})
    : runner = runner ?? ProcessRunner(environment: catalog.processEnvironment);

  final WorkspaceCatalog catalog;
  final ProcessRunner runner;

  Future<void> run(TestTarget target) async {
    switch (target) {
      case TestTarget.integration:
        final environment = await environmentFor(const [
          'STEM_TEST_REDIS_URL',
          'STEM_TEST_POSTGRES_URL',
        ]);
        final resolvedEnvironment = await resolveDependencies(
          environment: environment,
        );
        await runNoEnvironment(resolvedEnvironment);
      case TestTarget.noEnvironment:
        await runNoEnvironment();
      case TestTarget.flutter:
        await runFlutter();
      case TestTarget.all:
        await run(TestTarget.integration);
        await runFlutter();
      case TestTarget.contract:
        final environment = await environmentFor(const [
          'STEM_TEST_REDIS_URL',
          'STEM_TEST_POSTGRES_URL',
        ]);
        final resolvedEnvironment = await resolveDependencies(
          environment: environment,
        );
        await _runDartPackages(const [
          'packages/stem_adapter_tests',
          'packages/stem_memory',
          'packages/stem_sqlite',
          'packages/stem_redis',
          'packages/stem_postgres',
        ], environment: resolvedEnvironment);
      case TestTarget.redis:
        final environment = await environmentFor(const ['STEM_TEST_REDIS_URL']);
        final resolvedEnvironment = await resolveDependencies(
          environment: environment,
        );
        await _runDartPackages(const [
          'packages/stem_redis',
        ], environment: resolvedEnvironment);
      case TestTarget.postgres:
        final environment = await environmentFor(const [
          'STEM_TEST_POSTGRES_URL',
        ]);
        final resolvedEnvironment = await resolveDependencies(
          environment: environment,
        );
        await _runDartPackages(const [
          'packages/stem_postgres',
        ], environment: resolvedEnvironment);
    }
  }

  Future<Map<String, String>> resolveDependencies({
    Map<String, String>? environment,
  }) async {
    final pubTool = await Toolchain.pubTool();
    final resolvedEnvironment = {
      ...catalog.processEnvironment,
      ...?environment,
    };
    if (pubTool == 'flutter') {
      resolvedEnvironment['FLUTTER_ROOT'] = await Toolchain.flutterRoot();
    }
    await runner.run(
      pubTool,
      ['pub', 'get'],
      workingDirectory: catalog.root,
      environment: resolvedEnvironment,
      label: 'resolve root workspace',
    );

    // The dashboard is an experimental companion outside the workspace. Its
    // Routed dependency graph is validated by the explicit dashboard tasks,
    // not by the core Stem gate.
    return resolvedEnvironment;
  }

  Future<void> runNoEnvironment([Map<String, String>? environment]) async {
    await _runDartPackages(
      const [
        'packages/stem',
        'packages/stem_adapter_tests',
        'packages/stem_builder',
        'packages/stem_cli',
        'packages/stem_memory',
        'packages/stem_postgres',
        'packages/stem_redis',
        'packages/stem_sqlite',
      ],
      environment: environment,
      stemCliMulti: true,
    );
  }

  Future<void> runFlutter() async {
    for (final package in catalog.packages.where(
      (package) => package.isFlutter,
    )) {
      await runner.run(
        'flutter',
        ['pub', 'get'],
        workingDirectory: package.directory,
        label: 'resolve ${package.relativePath}',
      );
      await runner.run(
        'dart',
        ['format', '--output=none', '--set-exit-if-changed', 'lib', 'test'],
        workingDirectory: package.directory,
        label: 'format ${package.relativePath}',
      );
      await runner.run(
        'flutter',
        ['analyze', '--fatal-infos'],
        workingDirectory: package.directory,
        label: 'analyze ${package.relativePath}',
      );
      await runner.run(
        'flutter',
        ['test'],
        workingDirectory: package.directory,
        label: 'test ${package.relativePath}',
      );
    }
  }

  Future<void> _runDartPackages(
    Iterable<String> paths, {
    Map<String, String>? environment,
    bool stemCliMulti = false,
  }) async {
    for (final path in paths) {
      final package = _package(path);
      final applyMulti = stemCliMulti && package.name == 'stem_cli';
      Map<String, String>? packageEnvironment;
      if (environment != null) {
        packageEnvironment = Map<String, String>.from(environment);
      } else if (applyMulti) {
        packageEnvironment = Map<String, String>.from(
          catalog.processEnvironment,
        );
      }
      if (applyMulti) {
        packageEnvironment!['STEM_CLI_RUN_MULTI'] = 'true';
      }
      await runner.run(
        'dart',
        ['test', '--fail-fast'],
        workingDirectory: package.directory,
        environment: packageEnvironment,
        label: 'test $path',
      );
    }
  }

  WorkspacePackage _package(String path) {
    final matches = catalog.select(
      requestedPaths: [path],
      includeFlutter: true,
    );
    if (matches.length != 1) {
      throw StateError('Expected exactly one package at $path.');
    }
    return matches.single;
  }

  Future<Map<String, String>> environmentFor(
    Iterable<String> requiredVariables,
  ) async {
    final environment = catalog.processEnvironment;
    final required = requiredVariables.toList(growable: false);
    bool hasValue(String name) {
      final value = environment[name];
      return value != null && value.trim().isNotEmpty;
    }

    if (required.every(hasValue)) return environment;
    if (Platform.isWindows) {
      throw StateError(
        'Integration services are not bootstrapped automatically on Windows. '
        'Set the STEM_TEST_* variables before running this command.',
      );
    }

    final result = await Process.run(
      'bash',
      [
        '-lc',
        'set -e; source ./packages/stem_cli/_init_test_env >/dev/stderr 2>&1; env',
      ],
      workingDirectory: catalog.root.path,
      environment: environment,
    );
    if (result.stderr.toString().isNotEmpty) {
      stderr.write(result.stderr);
    }
    if (result.exitCode != 0) {
      throw ProcessException(
        'bash',
        ['-lc', 'source ./packages/stem_cli/_init_test_env'],
        result.stderr.toString(),
        result.exitCode,
      );
    }

    for (final line in result.stdout.toString().split('\n')) {
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      environment[line.substring(0, separator)] = line.substring(separator + 1);
    }
    final missing = required.where((name) => !hasValue(name));
    if (missing.isNotEmpty) {
      throw StateError(
        'Could not bootstrap required integration variables: '
        '${missing.join(', ')}',
      );
    }
    return environment;
  }
}
