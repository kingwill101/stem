import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:path/path.dart' as p;

import '../infrastructure/process_runner.dart';
import '../infrastructure/toolchain.dart';
import '../infrastructure/workspace.dart';

final class StandaloneDartCommand extends Command<int> {
  final bool flutterOnly;

  StandaloneDartCommand({this.flutterOnly = false}) {
    argParser.addMultiOption(
      'package',
      help: 'Limit resolution checks to one or more package paths.',
      valueHelp: 'packages/stem',
    );
  }

  @override
  String get name => flutterOnly ? 'standalone:flutter' : 'standalone:dart';

  @override
  String get description => flutterOnly
      ? 'Resolve Flutter packages outside workspace overrides.'
      : 'Resolve Dart packages outside workspace overrides.';

  @override
  Future<int> run() async {
    final catalog = WorkspaceCatalog.load();
    final requested = (argResults?['package'] as List<String>?) ?? const [];
    if (requested.contains('repodoc')) {
      throw ArgumentError(
        'repodoc is a private repository tool, not a standalone package.',
      );
    }
    final packages = catalog
        .select(
          requestedPaths: requested,
          includeFlutter: flutterOnly,
          workspaceOnly: true,
        )
        .where(
          (package) =>
              package.name != 'repodoc' && package.isFlutter == flutterOnly,
        )
        .toList(growable: false);
    if (packages.isEmpty) {
      throw StateError('No packages matched the requested resolution scope.');
    }
    final root = catalog.root;
    final runner = ProcessRunner(environment: catalog.processEnvironment);
    final pubTool = flutterOnly ? 'flutter' : await Toolchain.pubTool();
    await runner.run(
      pubTool,
      ['pub', 'get'],
      workingDirectory: root,
      label: 'resolve root workspace',
    );

    final staging = await catalog.temporaryDirectory.createTemp(
      'stem-standalone-',
    );
    try {
      for (final package in packages) {
        final output = Directory(
          p.join(staging.path, p.basename(package.relativePath)),
        )..createSync(recursive: true);
        final stagedOutput = await runner.capture('dart', [
          'run',
          'tool/stage_workspace.dart',
          '--package',
          package.relativePath,
          '--output',
          output.path,
        ], workingDirectory: root);
        final stagedLines = stagedOutput
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList(growable: false);
        final stagedPath = stagedLines.isEmpty ? null : stagedLines.last;
        if (stagedPath == null || !Directory(stagedPath).existsSync()) {
          throw StateError(
            'Workspace staging did not return a valid directory for '
            '${package.relativePath}.',
          );
        }
        await runner.run(
          pubTool,
          ['pub', 'get'],
          workingDirectory: Directory(stagedPath),
          label: 'standalone ${package.relativePath}',
        );
      }
    } finally {
      await staging.delete(recursive: true);
    }
    return 0;
  }
}
