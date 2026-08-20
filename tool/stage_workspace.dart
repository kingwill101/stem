import 'dart:io';

import 'package:yaml/yaml.dart';

Future<void> main(List<String> args) async {
  final packageName = _option(args, '--package');
  final outputPath = _option(args, '--output');
  if (packageName == null || outputPath == null) {
    stderr.writeln(
      'Usage: dart run tool/stage_workspace.dart '
      '--package <path> --output <directory>',
    );
    exitCode = 64;
    return;
  }

  final sourceRoot = Directory.current;
  final sourcePackages = Directory('${sourceRoot.path}/packages');
  final packageEntries = <String, _PackageEntry>{};
  for (final entity in sourcePackages.listSync()) {
    if (entity is! Directory) continue;
    final pubspec = File('${entity.path}/pubspec.yaml');
    if (!pubspec.existsSync()) continue;
    final yaml = loadYaml(pubspec.readAsStringSync());
    final name = yaml['name'];
    if (name is String) {
      packageEntries[name] = _PackageEntry(name: name, source: entity);
    }
  }

  final selectedSource = Directory('${sourceRoot.path}/$packageName');
  final selectedPubspec = File('${selectedSource.path}/pubspec.yaml');
  if (!selectedSource.existsSync() || !selectedPubspec.existsSync()) {
    stderr.writeln('Unknown package path: $packageName');
    exitCode = 64;
    return;
  }
  final selectedEntry = packageEntries.values.firstWhere(
    (entry) => entry.source.path == selectedSource.path,
  );
  final requiredPackages = <String>{selectedEntry.name};
  final pendingPackages = <String>[selectedEntry.name];
  while (pendingPackages.isNotEmpty) {
    final current = pendingPackages.removeLast();
    final yaml = loadYaml(
      File(
        '${packageEntries[current]!.source.path}/pubspec.yaml',
      ).readAsStringSync(),
    );
    for (final dependency in _localDependencyNames(yaml, packageEntries)) {
      if (requiredPackages.add(dependency)) {
        pendingPackages.add(dependency);
      }
    }
  }

  final outputRoot = Directory(outputPath);
  if (outputRoot.existsSync()) {
    if (outputRoot.listSync().isNotEmpty) {
      throw StateError('Staging output directory is not empty: $outputPath');
    }
  } else {
    outputRoot.createSync(recursive: true);
  }
  final stagedPackages = Directory('${outputRoot.path}/packages')
    ..createSync(recursive: true);

  final directoryByName = <String, String>{};
  for (final entry in packageEntries.values.where(
    (entry) => requiredPackages.contains(entry.name),
  )) {
    final destination = Directory('${stagedPackages.path}/${entry.sourceName}');
    _copyDirectory(entry.source, destination);
    directoryByName[entry.name] = entry.sourceName;
    final pubspec = File('${destination.path}/pubspec.yaml');
    final contents = pubspec.readAsStringSync().replaceFirst(
      RegExp(r'^resolution:\s*workspace\s*\n', multiLine: true),
      '',
    );
    pubspec.writeAsStringSync(contents);
  }

  for (final entry in packageEntries.values.where(
    (entry) => requiredPackages.contains(entry.name),
  )) {
    final stagedDirectory = Directory(
      '${stagedPackages.path}/${entry.sourceName}',
    );
    final sourceYaml = loadYaml(
      File('${entry.source.path}/pubspec.yaml').readAsStringSync(),
    );
    final localDependencies = <String, String>{};
    for (final name in _localDependencyNames(sourceYaml, packageEntries)) {
      final sourceName = directoryByName[name];
      if (sourceName != null && sourceName != entry.sourceName) {
        localDependencies[name] = '../$sourceName';
      }
    }
    if (localDependencies.isEmpty) continue;

    final overrides = StringBuffer('dependency_overrides:\n');
    for (final dependency in localDependencies.entries) {
      overrides
        ..writeln('  ${dependency.key}:')
        ..writeln('    path: ${dependency.value}');
    }
    File(
      '${stagedDirectory.path}/pubspec_overrides.yaml',
    ).writeAsStringSync(overrides.toString());
  }

  final selectedDirectory = Directory(
    '${stagedPackages.path}/${selectedEntry.sourceName}',
  );
  stdout.writeln(selectedDirectory.path);
}

Iterable<String> _localDependencyNames(
  dynamic yaml,
  Map<String, _PackageEntry> packageEntries,
) sync* {
  for (final section in const [
    'dependencies',
    'dev_dependencies',
    'dependency_overrides',
  ]) {
    final dependencies = yaml[section];
    if (dependencies is! YamlMap) continue;
    for (final dependency in dependencies.keys) {
      final name = dependency.toString();
      if (packageEntries.containsKey(name)) yield name;
    }
  }
}

String? _option(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) return null;
  return args[index + 1];
}

void _copyDirectory(Directory source, Directory destination) {
  destination.createSync(recursive: true);
  for (final entity in source.listSync()) {
    final name = entity.path
        .split(Platform.pathSeparator)
        .where((part) => part.isNotEmpty)
        .last;
    if (name == '.dart_tool' || name == 'build' || name == 'example') {
      continue;
    }
    if (entity is Directory) {
      _copyDirectory(entity, Directory('${destination.path}/$name'));
    } else if (entity is File) {
      File(
        '${destination.path}/$name',
      ).writeAsBytesSync(entity.readAsBytesSync());
    }
  }
}

final class _PackageEntry {
  _PackageEntry({required this.name, required this.source});

  final String name;
  final Directory source;

  String get sourceName => source.path.split(Platform.pathSeparator).last;
}
