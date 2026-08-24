import 'package:artisanal/args.dart';

import '../infrastructure/process_runner.dart';
import '../infrastructure/workspace.dart';

final class QualityDartCommand extends Command<int> {
  QualityDartCommand() {
    argParser
      ..addMultiOption(
        'package',
        help: 'Limit checks to one or more package paths.',
        valueHelp: 'packages/stem',
      )
      ..addFlag(
        'include-flutter',
        help: 'Include Flutter packages in the local quality pass.',
        negatable: false,
      )
      ..addFlag(
        'workspace-only',
        help: 'Exclude auxiliary packages from the quality pass.',
        negatable: false,
      );
  }

  @override
  String get name => 'quality:dart';

  @override
  String get description => 'Format and analyze the selected Dart packages.';

  @override
  Future<int> run() async {
    final catalog = WorkspaceCatalog.load();
    final packages = catalog.select(
      requestedPaths: (argResults?['package'] as List<String>?) ?? const [],
      includeFlutter: argResults?['include-flutter'] == true,
      workspaceOnly: argResults?['workspace-only'] == true,
    );
    if (packages.isEmpty) {
      throw StateError('No packages matched the requested quality scope.');
    }

    final runner = ProcessRunner(environment: catalog.processEnvironment);
    for (final package in packages) {
      final formatTargets = <String>[
        if (package.hasLib) 'lib',
        if (package.hasTest) 'test',
      ];
      if (formatTargets.isNotEmpty) {
        await runner.run(
          'dart',
          [
            'format',
            '--output=none',
            '--set-exit-if-changed',
            ...formatTargets,
          ],
          workingDirectory: package.directory,
          label: 'format ${package.relativePath}',
        );
      }
      await runner.run(
        package.isFlutter ? 'flutter' : 'dart',
        ['analyze', '--fatal-infos'],
        workingDirectory: package.directory,
        label: 'analyze ${package.relativePath}',
      );
    }
    return 0;
  }
}
