import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Resolves, generates, analyzes, and verifies every example in the root
/// workspace. Examples are executable documentation and must stay in sync
/// with the package APIs they demonstrate.
Future<void> main(List<String> args) async {
  final skipDiff = args.contains('--skip-diff');
  final unknown = args.where((arg) => arg != '--skip-diff').toList();
  if (unknown.isNotEmpty) {
    stderr.writeln('Unknown option(s): ${unknown.join(', ')}');
    exitCode = 64;
    return;
  }

  final workspace = _workspacePackages();
  final examples = <_ExampleProject>[];
  for (final packagePath in workspace) {
    final exampleRoot = Directory(p.join(packagePath, 'example'));
    if (!exampleRoot.existsSync()) continue;

    await for (final entity in exampleRoot.list(recursive: true)) {
      if (entity is! File || p.basename(entity.path) != 'pubspec.yaml') {
        continue;
      }
      final relativeParts = p.split(
        p.relative(entity.path, from: exampleRoot.path),
      );
      if (relativeParts.any(_isGeneratedExampleDirectory)) {
        continue;
      }
      final yaml = loadYaml(entity.readAsStringSync());
      if (yaml is! YamlMap) {
        throw StateError('${entity.path} is not a YAML map.');
      }
      final dependencies = {
        ..._dependencyNames(yaml['dependencies']),
        ..._dependencyNames(yaml['dev_dependencies']),
      };
      examples.add(
        _ExampleProject(
          path: p.dirname(entity.path),
          tool: dependencies.contains('flutter') ? 'flutter' : 'dart',
          hasBuildRunner: _dependencyNames(
            yaml['dev_dependencies'],
          ).contains('build_runner'),
        ),
      );
    }
  }

  examples.sort((a, b) => a.path.compareTo(b.path));
  if (examples.isEmpty) {
    throw StateError('No workspace examples were discovered.');
  }

  print('[INFO] Checking ${examples.length} workspace examples.');
  for (final example in examples) {
    final executable = example.tool;
    await _run(executable, const ['pub', 'get'], example.path);
    if (example.hasBuildRunner) {
      await _run('dart', const [
        'run',
        'build_runner',
        'build',
        '--delete-conflicting-outputs',
      ], example.path);
    }
    await _run(executable, const ['analyze', '--fatal-infos'], example.path);

    if (!skipDiff) {
      final relativePath = p.relative(example.path);
      final diff = await Process.run('git', [
        'diff',
        '--exit-code',
        '--',
        relativePath,
      ]);
      final status = await Process.run('git', [
        'status',
        '--porcelain',
        '--',
        relativePath,
      ]);
      if (diff.exitCode != 0 || (status.stdout as String).trim().isNotEmpty) {
        throw StateError(
          'Generated or analyzed files changed in $relativePath. '
          'Commit the example output before merging.',
        );
      }
    }
  }
  print('[SUCCESS] Workspace examples are valid.');
}

List<String> _workspacePackages() {
  final file = File('pubspec.yaml');
  if (!file.existsSync()) {
    throw StateError('Run this tool from the repository root.');
  }
  final yaml = loadYaml(file.readAsStringSync());
  if (yaml is! YamlMap || yaml['workspace'] is! YamlList) {
    throw StateError('Root pubspec.yaml has no workspace package list.');
  }
  return (yaml['workspace'] as YamlList)
      .map((value) => value.toString())
      .toList();
}

Set<String> _dependencyNames(Object? value) {
  if (value is! YamlMap) return <String>{};
  return value.keys.map((key) => key.toString()).toSet();
}

bool _isGeneratedExampleDirectory(String part) =>
    part == '.dart_tool' ||
    part == 'build' ||
    part == 'ephemeral' ||
    part == '.plugin_symlinks' ||
    part == 'android' ||
    part == 'ios' ||
    part == 'linux' ||
    part == 'macos' ||
    part == 'web' ||
    part == 'windows';

Future<void> _run(
  String executable,
  List<String> arguments,
  String directory,
) async {
  print('[RUN] $directory: $executable ${arguments.join(' ')}');
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: directory,
    runInShell: true,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      'Command failed in $directory',
      result.exitCode,
    );
  }
}

final class _ExampleProject {
  const _ExampleProject({
    required this.path,
    required this.tool,
    required this.hasBuildRunner,
  });

  final String path;
  final String tool;
  final bool hasBuildRunner;
}
