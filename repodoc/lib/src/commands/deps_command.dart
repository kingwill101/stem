import 'dart:io';

import 'package:artisanal/args.dart';

import '../infrastructure/process_runner.dart';
import '../infrastructure/workspace.dart';

final class DepsCommand extends Command<int> {
  @override
  String get name => 'deps';

  @override
  String get description => 'Resolve workspace and dashboard dependencies.';

  @override
  Future<int> run() async {
    final catalog = WorkspaceCatalog.load();
    final runner = ProcessRunner(environment: catalog.processEnvironment);
    final pubTool = await _pubTool();
    await runner.run(
      pubTool,
      ['pub', 'get'],
      workingDirectory: catalog.root,
      label: 'resolve root workspace',
    );

    final dashboard = catalog.select(
      requestedPaths: const ['packages/dashboard'],
      includeFlutter: true,
    );
    if (dashboard.isNotEmpty) {
      await runner.run(
        pubTool,
        ['pub', 'get'],
        workingDirectory: dashboard.single.directory,
        label: 'resolve packages/dashboard',
      );
    }
    return 0;
  }

  Future<String> _pubTool() async {
    final lookup = await Process.run(Platform.isWindows ? 'where' : 'which', [
      'flutter',
    ]);
    return lookup.exitCode == 0 ? 'flutter' : 'dart';
  }
}
