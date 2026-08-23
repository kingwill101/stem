#!/usr/bin/env dartrun

import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

/// Release automation for the publishable packages in the Dart workspace.
///
/// The tool intentionally derives package order and membership from the root
/// workspace and package manifests. A release must not silently omit a newly
/// added package or publish a dependent package before its dependencies.
Future<void> main(List<String> args) async {
  final options = _ReleaseOptions.parse(args);
  final workspace = await _loadWorkspace();

  print('--- Stem Release Automation ---');
  print(options.isDryRun ? '[MODE] Dry run' : '[MODE] ACTUAL PUBLISH');

  if (options.allowDirty && !options.planOnly) {
    throw StateError(
      '--allow-dirty is restricted to release planning; run the full release '
      'gate from a clean worktree so pub.dev validates the exact commit.',
    );
  }

  if (!options.allowDirty && await _hasDirtyTree()) {
    throw StateError(
      'The Git worktree is dirty. Commit release metadata before publishing, '
      'or pass --allow-dirty for an explicitly non-reproducible dry run.',
    );
  }

  final ordered = _topologicallySort(workspace.publishablePackages);
  final selected = await _selectPackages(
    ordered,
    includeUnchanged: options.includeUnchanged,
  );

  if (selected.isEmpty) {
    print('No changed publishable packages found.');
    return;
  }

  print(
    '[INFO] Release order: ${selected.map((pkg) => pkg.name).join(' -> ')}',
  );

  if (options.planOnly) {
    return;
  }

  for (final package in selected) {
    await _validatePackage(package, checkGenerated: options.checkGenerated);
  }

  for (final package in selected) {
    final lookup = await _fetchPubPackageInfo(package.name);
    if (!lookup.reachable) {
      throw StateError(
        'Could not verify pub.dev state for ${package.name}; refusing to '
        'treat an unreachable registry as unpublished.',
      );
    }
    final latest = _latestVersion(lookup.versions);
    if (latest != null && _compareVersions(latest, package.version!) > 0) {
      throw StateError(
        '${package.name} is behind pub.dev: local ${package.version}, '
        'published $latest. Recover the release metadata before publishing.',
      );
    }
    if (lookup.versions.contains(package.version)) {
      if (options.skipPublished) {
        print(
          '[INFO] Skipping ${package.name} ${package.version}: already published.',
        );
        continue;
      }
      throw StateError(
        '${package.name} ${package.version} is already published. Bump the '
        'version and add its changelog entry before releasing.',
      );
    }

    await _publishPackage(package, isDryRun: options.isDryRun);
  }

  print('[SUCCESS] Release checks completed.');
}

class _ReleaseOptions {
  const _ReleaseOptions({
    required this.isDryRun,
    required this.allowDirty,
    required this.includeUnchanged,
    required this.skipPublished,
    required this.checkGenerated,
    required this.planOnly,
  });

  final bool isDryRun;
  final bool allowDirty;
  final bool includeUnchanged;
  final bool skipPublished;
  final bool checkGenerated;
  final bool planOnly;

  factory _ReleaseOptions.parse(List<String> args) {
    final known = {
      '--allow-dirty',
      '--check-generated',
      '--force',
      '--include-unchanged',
      '--plan',
      '--skip-generated',
      '--skip-published',
    };
    final unknown = args.where((arg) => !known.contains(arg));
    if (unknown.isNotEmpty) {
      throw ArgumentError('Unknown release option(s): ${unknown.join(', ')}');
    }
    return _ReleaseOptions(
      isDryRun: !args.contains('--force'),
      allowDirty: args.contains('--allow-dirty'),
      includeUnchanged: args.contains('--include-unchanged'),
      skipPublished: args.contains('--skip-published'),
      checkGenerated: !args.contains('--skip-generated'),
      planOnly: args.contains('--plan'),
    );
  }
}

class _Workspace {
  const _Workspace(this.publishablePackages);

  final List<_Package> publishablePackages;
}

class _Package {
  const _Package({
    required this.path,
    required this.name,
    required this.version,
    required this.dependencies,
    required this.isFlutter,
    required this.hasBuildRunner,
  });

  final String path;
  final String name;
  final String? version;
  final Set<String> dependencies;
  final bool isFlutter;
  final bool hasBuildRunner;
}

Future<_Workspace> _loadWorkspace() async {
  final rootFile = File('pubspec.yaml');
  if (!rootFile.existsSync()) {
    throw StateError('Run the release tool from the repository root.');
  }

  final root = loadYaml(rootFile.readAsStringSync());
  if (root is! YamlMap || root['workspace'] is! YamlList) {
    throw StateError('Root pubspec.yaml has no workspace package list.');
  }

  final packages = <_Package>[];
  for (final rawPath in root['workspace'] as YamlList) {
    final path = rawPath.toString();
    final pubspecFile = File('$path/pubspec.yaml');
    if (!pubspecFile.existsSync()) {
      throw StateError('Workspace entry $path has no pubspec.yaml.');
    }

    final manifest = loadYaml(pubspecFile.readAsStringSync());
    if (manifest is! YamlMap) {
      throw StateError('$path/pubspec.yaml is not a YAML map.');
    }
    final publishTo = manifest['publish_to']?.toString();
    if (publishTo == 'none') {
      continue;
    }

    final name = manifest['name']?.toString();
    if (name == null || name.isEmpty) {
      throw StateError('$path/pubspec.yaml has no package name.');
    }
    final dependencies = <String>{
      ..._dependencyNames(manifest['dependencies']),
      ..._dependencyNames(manifest['dependency_overrides']),
    };
    final devDependencies = _dependencyNames(manifest['dev_dependencies']);
    packages.add(
      _Package(
        path: path,
        name: name,
        version: manifest['version']?.toString(),
        dependencies: dependencies,
        isFlutter: dependencies.contains('flutter'),
        hasBuildRunner: devDependencies.contains('build_runner'),
      ),
    );
  }

  return _Workspace(packages);
}

Set<String> _dependencyNames(Object? value) {
  if (value is! YamlMap) return <String>{};
  return value.keys.map((key) => key.toString()).toSet();
}

List<_Package> _topologicallySort(List<_Package> packages) {
  final byName = {for (final package in packages) package.name: package};
  final state = <String, int>{};
  final ordered = <_Package>[];

  void visit(_Package package, List<String> chain) {
    final currentState = state[package.name] ?? 0;
    if (currentState == 2) return;
    if (currentState == 1) {
      final cycle = [...chain, package.name].join(' -> ');
      throw StateError('Workspace package dependency cycle: $cycle');
    }
    state[package.name] = 1;
    for (final dependencyName in package.dependencies) {
      final dependency = byName[dependencyName];
      if (dependency != null) {
        visit(dependency, [...chain, package.name]);
      }
    }
    state[package.name] = 2;
    ordered.add(package);
  }

  for (final package in packages) {
    visit(package, const []);
  }
  return ordered;
}

Future<List<_Package>> _selectPackages(
  List<_Package> ordered, {
  required bool includeUnchanged,
}) async {
  if (includeUnchanged) return ordered;

  final changed = <String>{};
  for (final package in ordered) {
    final baselineRef = await _resolveBaselineRef(package.name);
    if (baselineRef == null) {
      changed.add(package.name);
      continue;
    }
    if (await _packageChangedSince(package.path, baselineRef)) {
      changed.add(package.name);
    }
  }

  // A changed package must bring changed dependents through the release gate;
  // otherwise a dependency update can be published without its compatible
  // downstream package being validated or released.
  var expanded = true;
  while (expanded) {
    expanded = false;
    for (final package in ordered) {
      if (changed.contains(package.name)) continue;
      if (package.dependencies.any(changed.contains)) {
        changed.add(package.name);
        expanded = true;
      }
    }
  }
  return ordered.where((package) => changed.contains(package.name)).toList();
}

Future<void> _validatePackage(
  _Package package, {
  required bool checkGenerated,
}) async {
  await _run('dart', [
    'format',
    'lib',
    'test',
    '--set-exit-if-changed',
  ], package);
  final executable = package.isFlutter ? 'flutter' : 'dart';
  await _run(executable, ['analyze', '--fatal-infos'], package);
  final testArguments = <String>['test', '--fail-fast'];
  if (package.path == 'packages/stem') {
    testArguments.insert(1, '--exclude-tags');
    testArguments.insert(2, 'soak');
  }
  await _run(executable, testArguments, package);

  if (checkGenerated && package.hasBuildRunner) {
    await _run('dart', [
      'run',
      'build_runner',
      'build',
      '--delete-conflicting-outputs',
    ], package);
    await _runGitDiffCheck(package.path);
  }

  final changelog = File('${package.path}/CHANGELOG.md');
  if (!changelog.existsSync()) {
    throw StateError('${package.name} has no CHANGELOG.md.');
  }
  final version = package.version;
  if (version == null || version.isEmpty) {
    throw StateError('${package.name} has no version.');
  }
  final versionHeading = RegExp(
    r'^##\s+' + RegExp.escape(version) + r'(?:\s|$)',
    multiLine: true,
  );
  if (!versionHeading.hasMatch(changelog.readAsStringSync())) {
    throw StateError(
      '${package.name} CHANGELOG.md has no heading for version $version.',
    );
  }

  await _run('dart', ['pub', 'publish', '--dry-run'], package);
}

Future<void> _publishPackage(_Package package, {required bool isDryRun}) async {
  if (isDryRun) {
    print('[DRY-RUN] ${package.name} ${package.version} is publishable.');
    return;
  }
  await _run('dart', ['pub', 'publish', '--force'], package);
}

Future<void> _run(
  String executable,
  List<String> arguments,
  _Package package,
) async {
  print('[RUN] ${package.name}: $executable ${arguments.join(' ')}');
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: package.path,
    runInShell: true,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      'Command failed for ${package.name}',
      result.exitCode,
    );
  }
}

Future<void> _runGitDiffCheck(String path) async {
  final result = await Process.run('git', ['diff', '--quiet', '--', path]);
  final status = await Process.run('git', [
    'status',
    '--porcelain',
    '--',
    path,
  ]);
  if (result.exitCode != 0 || (status.stdout as String).trim().isNotEmpty) {
    throw StateError(
      'Generated files for $path are out of date. Run the generator and '
      'commit its output before releasing.',
    );
  }
}

Future<bool> _hasDirtyTree() async {
  final result = await Process.run('git', ['status', '--porcelain']);
  if (result.exitCode != 0) {
    throw StateError('Unable to inspect Git worktree state.');
  }
  return (result.stdout as String).trim().isNotEmpty;
}

Future<String?> _resolveBaselineRef(String packageName) async {
  final result = await Process.run('git', [
    'describe',
    '--tags',
    '--match',
    '$packageName-v*',
    '--abbrev=0',
  ]);
  if (result.exitCode != 0) return null;
  final tag = (result.stdout as String).trim();
  return tag.isEmpty ? null : tag;
}

Future<bool> _packageChangedSince(String path, String baselineRef) async {
  final result = await Process.run('git', [
    'diff',
    '--name-only',
    '$baselineRef...HEAD',
    '--',
    path,
  ]);
  if (result.exitCode != 0) {
    throw StateError('Unable to inspect changes for $path.');
  }
  return (result.stdout as String).trim().isNotEmpty;
}

class _PubPackageInfo {
  const _PubPackageInfo({required this.reachable, required this.versions});

  final bool reachable;
  final Set<String> versions;
}

String? _latestVersion(Iterable<String> versions) {
  if (versions.isEmpty) return null;
  return versions.reduce(
    (current, candidate) =>
        _compareVersions(candidate, current) > 0 ? candidate : current,
  );
}

int _compareVersions(String left, String right) {
  final leftParts = _versionParts(left);
  final rightParts = _versionParts(right);
  for (var index = 0; index < 3; index++) {
    final comparison = leftParts[index].compareTo(rightParts[index]);
    if (comparison != 0) return comparison;
  }
  return 0;
}

List<int> _versionParts(String value) {
  final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(value);
  if (match == null) return const [0, 0, 0];
  return [
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  ];
}

Future<_PubPackageInfo> _fetchPubPackageInfo(String packageName) async {
  final client = HttpClient();
  try {
    final uri = Uri.https('pub.dev', '/api/packages/$packageName');
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      return const _PubPackageInfo(reachable: false, versions: {});
    }
    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      return const _PubPackageInfo(reachable: false, versions: {});
    }
    final versions = <String>{};
    final entries = decoded['versions'];
    if (entries is List) {
      for (final entry in entries) {
        if (entry is Map<String, dynamic> && entry['version'] is String) {
          versions.add(entry['version'] as String);
        }
      }
    }
    return _PubPackageInfo(reachable: true, versions: versions);
  } on Object {
    return const _PubPackageInfo(reachable: false, versions: {});
  } finally {
    client.close(force: true);
  }
}
