import 'dart:io';

import 'package:artisanal/args.dart';

import '../infrastructure/process_runner.dart';
import '../infrastructure/workspace.dart';

enum DemoTarget { annotated, builder, ecommerce, all }

final class DemoCommand extends Command<int> {
  DemoCommand(this.target);

  final DemoTarget target;

  @override
  String get name => switch (target) {
    DemoTarget.annotated => 'demo:annotated',
    DemoTarget.builder => 'demo:builder',
    DemoTarget.ecommerce => 'demo:ecommerce:test',
    DemoTarget.all => 'demo:all',
  };

  @override
  String get description => switch (target) {
    DemoTarget.annotated => 'Run the annotated workflows example.',
    DemoTarget.builder => 'Run the stem_builder example.',
    DemoTarget.ecommerce => 'Run the ecommerce example test suite.',
    DemoTarget.all => 'Run the healthy example demos from the repository root.',
  };

  @override
  Future<int> run() async {
    final runner = DemoRunner(WorkspaceCatalog.load());
    await runner.run(target);
    return 0;
  }
}

final class DemoRunner {
  DemoRunner(this.catalog, {ProcessRunner? runner})
    : runner = runner ?? ProcessRunner(environment: catalog.processEnvironment);

  final WorkspaceCatalog catalog;
  final ProcessRunner runner;

  Future<void> run(DemoTarget target) async {
    switch (target) {
      case DemoTarget.annotated:
        await _run('packages/stem/example/annotated_workflows', const [
          'run',
          'bin/main.dart',
        ]);
      case DemoTarget.builder:
        await _run('packages/stem_builder/example', const [
          'run',
          'bin/main.dart',
        ]);
      case DemoTarget.ecommerce:
        await _run('packages/stem/example/ecommerce', const ['test']);
      case DemoTarget.all:
        await run(DemoTarget.annotated);
        await run(DemoTarget.builder);
        await run(DemoTarget.ecommerce);
    }
  }

  Future<void> _run(String relativePath, List<String> command) async {
    final package = DirectoryPackage(catalog.root, relativePath);
    await runner.run(
      'dart',
      const ['pub', 'get'],
      workingDirectory: package.directory,
      label: 'resolve $relativePath',
    );
    await runner.run(
      'dart',
      const ['run', 'build_runner', 'build', '--delete-conflicting-outputs'],
      workingDirectory: package.directory,
      label: 'generate $relativePath',
    );
    await runner.run(
      'dart',
      command,
      workingDirectory: package.directory,
      label: 'run $relativePath',
    );
  }
}

final class DirectoryPackage {
  DirectoryPackage(this.root, this.relativePath);

  final Directory root;
  final String relativePath;

  Directory get directory => Directory('${root.path}/$relativePath');
}
