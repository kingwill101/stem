import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:path/path.dart' as p;

import '../infrastructure/process_runner.dart';
import '../infrastructure/workspace.dart';
import 'test_commands.dart';

enum CoverageTarget { withEnvironment, withoutEnvironment }

final class CoverageCommand extends Command<int> {
  CoverageCommand(this.target);

  final CoverageTarget target;

  @override
  String get name =>
      target == CoverageTarget.withEnvironment ? 'coverage' : 'coverage:no-env';

  @override
  String get description => target == CoverageTarget.withEnvironment
      ? 'Run coverage for the core packages with services bootstrapped.'
      : 'Run coverage for the core packages without service bootstrap.';

  @override
  Future<int> run() async {
    final catalog = WorkspaceCatalog.load();
    final orchestrator = TestOrchestrator(catalog);
    Map<String, String>? environment;
    if (target == CoverageTarget.withEnvironment) {
      environment = await orchestrator.environmentFor(const [
        'STEM_TEST_REDIS_URL',
        'STEM_TEST_POSTGRES_URL',
      ]);
      environment = await orchestrator.resolveDependencies(
        environment: environment,
      );
    }
    await CoverageRunner(catalog).run(environment: environment);
    return 0;
  }
}

final class PackageCoverageCommand extends Command<int> {
  PackageCoverageCommand() {
    argParser
      ..addOption('package', help: 'Package path to cover.')
      ..addOption('min', defaultsTo: '80')
      ..addFlag(
        'exclude-soak',
        help: 'Exclude soak tests from the coverage run.',
        negatable: false,
      );
  }

  @override
  String get name => 'coverage:package';

  @override
  String get description => 'Run coverage for one Dart package.';

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
    final minimum = double.tryParse(argResults?['min'] as String? ?? '');
    if (minimum == null || minimum < 0) {
      throw ArgumentError('Invalid coverage minimum: --min');
    }
    final environment = await TestOrchestrator(catalog).resolveDependencies();
    await CoverageRunner(catalog).runPackage(
      matches.single,
      minimumCoverage: minimum,
      excludeSoak: argResults?['exclude-soak'] == true,
      environment: environment,
    );
    return 0;
  }
}

final class CoverageRunner {
  CoverageRunner(this.catalog, {ProcessRunner? runner})
    : runner = runner ?? ProcessRunner(environment: catalog.processEnvironment);

  final WorkspaceCatalog catalog;
  final ProcessRunner runner;

  Future<void> run({Map<String, String>? environment}) async {
    const packagePaths = [
      'packages/stem',
      'packages/stem_cli',
      'packages/stem_postgres',
      'packages/stem_redis',
      'packages/stem_sqlite',
      'packages/stem_memory',
    ];
    for (final path in packagePaths) {
      await runPackage(
        _package(path),
        minimumCoverage: _minimumCoverage(path).toDouble(),
        excludeSoak: path == 'packages/stem',
        environment: environment,
      );
    }
  }

  Future<void> runPackage(
    WorkspacePackage package, {
    required double minimumCoverage,
    bool excludeSoak = false,
    Map<String, String>? environment,
  }) async {
    final coverageDirectory = Directory(
      p.join(package.directory.path, 'coverage'),
    );
    final packageEnvironment = package.name == 'stem_cli'
        ? {
            ...catalog.processEnvironment,
            ...?environment,
            'STEM_CLI_RUN_MULTI': 'true',
          }
        : environment;
    if (coverageDirectory.existsSync()) {
      await coverageDirectory.delete(recursive: true);
    }
    await runner.run(
      'dart',
      [
        'test',
        '--fail-fast',
        if (excludeSoak) '--exclude-tags',
        if (excludeSoak) 'soak',
        '--coverage=coverage',
      ],
      workingDirectory: package.directory,
      environment: packageEnvironment,
      label: 'coverage ${package.relativePath}',
    );
    if (!coverageDirectory.existsSync()) {
      throw StateError(
        'Coverage directory was not created for ${package.relativePath}.',
      );
    }
    await runner.run(
      'dart',
      [
        'run',
        'coverage:format_coverage',
        '--lcov',
        '--in=coverage',
        '--out=coverage/lcov.info',
        '--report-on=lib',
      ],
      workingDirectory: package.directory,
      environment: packageEnvironment,
      label: 'format coverage ${package.relativePath}',
    );
    final badgeScript = p.relative(
      p.join(catalog.root.path, 'tool/coverage/coverage_badge.dart'),
      from: package.directory.path,
    );
    await runner.run(
      'dart',
      [
        'run',
        badgeScript,
        '--lcov',
        'coverage/lcov.info',
        '--out',
        'coverage/coverage.json',
        '--min',
        minimumCoverage.toString(),
      ],
      workingDirectory: package.directory,
      environment: packageEnvironment,
      label: 'check coverage ${package.relativePath}',
    );
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

  int _minimumCoverage(String path) => switch (path) {
    'packages/stem_memory' => 0,
    _ => 80,
  };
}
