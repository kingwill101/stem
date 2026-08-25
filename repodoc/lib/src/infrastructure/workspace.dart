import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

final class WorkspaceCatalog {
  WorkspaceCatalog._({required this.root, required this.packages});

  final Directory root;
  final List<WorkspacePackage> packages;

  factory WorkspaceCatalog.load([Directory? root]) {
    final resolvedRoot = root ?? Directory.current;
    final pubspec = File(p.join(resolvedRoot.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      throw StateError(
        'Workspace root has no pubspec.yaml: ${resolvedRoot.path}',
      );
    }

    final document = loadYaml(pubspec.readAsStringSync());
    final entries = document['workspace'];
    if (entries is! YamlList) {
      throw StateError('Root pubspec.yaml must define a workspace list.');
    }

    final packages = <WorkspacePackage>[];
    final seenPaths = <String>{};
    for (final entry in entries) {
      if (entry is! String) {
        throw StateError('Workspace entries must be relative path strings.');
      }
      final relativePath = p.normalize(entry);
      if (!seenPaths.add(relativePath)) {
        throw StateError('Duplicate workspace entry: $relativePath');
      }
      packages.add(
        WorkspacePackage.load(
          root: resolvedRoot,
          relativePath: relativePath,
          workspaceMember: true,
        ),
      );
    }

    // dashboard intentionally remains outside Dart workspace resolution while
    // it is still a user-facing package that must pass repository quality
    // checks. Keep it discoverable without silently changing its dependency
    // graph.
    const auxiliaryPaths = ['packages/dashboard'];
    for (final relativePath in auxiliaryPaths) {
      if (seenPaths.contains(relativePath)) continue;
      final pubspecPath = File(
        p.join(resolvedRoot.path, relativePath, 'pubspec.yaml'),
      );
      if (!pubspecPath.existsSync()) continue;
      packages.add(
        WorkspacePackage.load(
          root: resolvedRoot,
          relativePath: relativePath,
          workspaceMember: false,
        ),
      );
    }

    final catalog = WorkspaceCatalog._(root: resolvedRoot, packages: packages);
    catalog.temporaryDirectory.createSync(recursive: true);
    return catalog;
  }

  /// Repository-local scratch space used by repodoc and its child processes.
  Directory get temporaryDirectory =>
      Directory(p.join(root.absolute.path, '.tmp'));

  /// Environment for subprocesses launched by repodoc.
  ///
  /// Dart uses `TMPDIR` on Unix and `TEMP`/`TMP` on Windows. Set all three so
  /// the same repository-local location is used by every supported tool.
  Map<String, String> get processEnvironment {
    final path = temporaryDirectory.absolute.path;
    return {...Platform.environment, 'TMP': path, 'TMPDIR': path, 'TEMP': path};
  }

  List<WorkspacePackage> select({
    Iterable<String>? requestedPaths,
    bool includeFlutter = false,
    bool workspaceOnly = false,
  }) {
    final requested = requestedPaths == null || requestedPaths.isEmpty
        ? null
        : requestedPaths.map(_normalizeRequestedPath).toSet();
    if (requested != null) {
      final known = packages.map((package) => package.relativePath).toSet();
      final unknown = requested.difference(known);
      if (unknown.isNotEmpty) {
        throw ArgumentError(
          'Unknown workspace package path(s): ${unknown.join(', ')}',
        );
      }
    }
    return packages
        .where((package) => !workspaceOnly || package.workspaceMember)
        .where((package) => includeFlutter || !package.isFlutter)
        .where(
          (package) =>
              requested == null || requested.contains(package.relativePath),
        )
        .toList(growable: false);
  }

  String _normalizeRequestedPath(String value) => p.normalize(value.trim());
}

final class WorkspacePackage {
  WorkspacePackage._({
    required this.root,
    required this.relativePath,
    required this.name,
    required this.workspaceMember,
    required this.isFlutter,
  });

  factory WorkspacePackage.load({
    required Directory root,
    required String relativePath,
    required bool workspaceMember,
  }) {
    final directory = Directory(p.join(root.path, relativePath));
    final pubspec = File(p.join(directory.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      throw StateError(
        'Workspace package is missing pubspec.yaml: $relativePath',
      );
    }
    final document = loadYaml(pubspec.readAsStringSync());
    final name = document['name'];
    if (name is! String || name.isEmpty) {
      throw StateError('Workspace package has no valid name: $relativePath');
    }
    return WorkspacePackage._(
      root: root,
      relativePath: p.normalize(relativePath),
      name: name,
      workspaceMember: workspaceMember,
      isFlutter: name.startsWith('stem_flutter'),
    );
  }

  final Directory root;
  final String relativePath;
  final String name;
  final bool workspaceMember;
  final bool isFlutter;

  Directory get directory => Directory(p.join(root.path, relativePath));

  bool get hasLib => Directory(p.join(directory.path, 'lib')).existsSync();

  bool get hasTest => Directory(p.join(directory.path, 'test')).existsSync();
}
