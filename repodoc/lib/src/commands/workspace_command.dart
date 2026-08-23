import 'dart:io';

import 'package:artisanal/args.dart';

import '../infrastructure/workspace.dart';

final class WorkspaceCheckCommand extends Command<int> {
  WorkspaceCheckCommand() {
    argParser.addFlag(
      'json',
      help: 'Emit the discovered package catalog as JSON.',
      negatable: false,
    );
  }

  @override
  String get name => 'workspace:check';

  @override
  String get description =>
      'Validate and display the workspace package catalog.';

  @override
  Future<int> run() async {
    final catalog = WorkspaceCatalog.load();
    final packages = catalog.packages;
    if (argResults?['json'] == true) {
      stdout.write('[${packages.map(_jsonPackage).join(',')}]\n');
      return 0;
    }
    stdout.writeln('Stem workspace packages (${packages.length}):');
    for (final package in packages) {
      final kind = package.isFlutter ? 'flutter' : 'dart';
      final scope = package.workspaceMember ? 'workspace' : 'auxiliary';
      stdout.writeln(
        '  ${package.relativePath} (${package.name}, $kind, $scope)',
      );
    }
    return 0;
  }

  String _jsonPackage(WorkspacePackage package) {
    return '{"name":"${_escape(package.name)}",'
        '"path":"${_escape(package.relativePath)}",'
        '"flutter":${package.isFlutter},'
        '"workspaceMember":${package.workspaceMember}}';
  }

  String _escape(String value) =>
      value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
}
