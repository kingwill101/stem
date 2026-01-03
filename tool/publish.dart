#!/usr/bin/env dartrun

import 'dart:convert';
import 'dart:io';

/// Packages to publish in dependency order.
final packages = [
  'packages/stem',
  'packages/stem_adapter_tests',
  'packages/stem_sqlite',
  'packages/stem_redis',
  'packages/stem_postgres',
  'packages/stem_cli',
];

Future<void> main(List<String> args) async {
  final isDryRun = !args.contains('--force');
  final includeUnchanged = args.contains('--include-unchanged');
  final skipPublished = args.contains('--skip-published');
  final baselineRef = await _resolveBaselineRef();

  print('--- Stem Release Automation ---');
  if (isDryRun) {
    print('[MODE] Dry Run (use --force to actually publish)');
  } else {
    print('[MODE] ACTUAL PUBLISH');
  }
  if (baselineRef == null) {
    print('[INFO] No release tag found. Processing all packages.');
  } else {
    print('[INFO] Baseline ref: $baselineRef');
  }
  if (includeUnchanged) {
    print('[INFO] Including unchanged packages.');
  }
  if (skipPublished) {
    print('[INFO] Skipping already published versions.');
  }

  try {
    for (final pkgPath in packages) {
      await _formatPackage(pkgPath);
    }

    for (final pkgPath in packages) {
      await publishPackage(
        pkgPath,
        isDryRun,
        baselineRef: baselineRef,
        includeUnchanged: includeUnchanged,
        skipPublished: skipPublished,
      );
    }
    print('\n[SUCCESS] All packages processed successfully!');
  } catch (e) {
    print('\n[FAILURE] Publishing interrupted: $e');
    exit(1);
  }
}

Future<void> _formatPackage(String pkgPath, {bool exitIfChanged = true}) async {
  final fullPath = _resolvePackagePath(pkgPath);

  print('\n--> Running dart format at $fullPath...');
  final process = await Process.start(
    'dart',
    [
      'format',
      '.',
      ...[if (exitIfChanged) '--set-exit-if-changed'],
    ],
    workingDirectory: fullPath,
    mode: ProcessStartMode.inheritStdio,
  );
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw Exception('dart format failed (exit code $exitCode)');
  }
  print('✓ dart format complete.');
}

Future<void> publishPackage(
  String pkgPath,
  bool isDryRun, {
  required String? baselineRef,
  required bool includeUnchanged,
  required bool skipPublished,
}) async {
  final fullPath = _resolvePackagePath(pkgPath);
  final pubspecFile = File('${fullPath}pubspec.yaml');

  if (!pubspecFile.existsSync()) {
    throw Exception('pubspec.yaml not found in $pkgPath');
  }

  final pubspec = _readPubspec(pubspecFile);
  final name = pubspec.name ?? _basename(pkgPath);
  final version = pubspec.version;
  if (!includeUnchanged) {
    final changed = await _packageChangedSince(pkgPath, baselineRef);
    if (!changed) {
      print(
        '\n--> Skipping $name ($pkgPath): no changes since ${baselineRef ?? 'initial commit'}.',
      );
      return;
    }
  }
  if (skipPublished && version != null) {
    final published = await _isVersionPublished(name, version);
    if (published) {
      print('\n--> Skipping $name ($pkgPath): $version already published.');
      return;
    }
  }
  print('\n--> Processing $name ($pkgPath)...');

  // 1. Dry run first (always)
  print('Running dry-run check...');
  final dryRunResult = await Process.run('dart', [
    'pub',
    'publish',
    '--dry-run',
  ], workingDirectory: fullPath);

  if (dryRunResult.exitCode != 0) {
    print('Dry-run failed for $name:');
    print(dryRunResult.stdout);
    print(dryRunResult.stderr);
    throw Exception('Dry-run failed for $name');
  }
  print('✓ Dry-run passed.');

  if (!isDryRun) {
    print('Publishing $name to pub.dev...');
    // We use inheritStdio to allow the user to see progress and handle any
    // unexpected prompts, though --force should skip them.
    final process = await Process.start(
      'dart',
      ['pub', 'publish', '--force'],
      workingDirectory: fullPath,
      mode: ProcessStartMode.inheritStdio,
    );

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw Exception('Failed to publish $name (exit code $exitCode)');
    }
    print('✓ Published $name.');
  }
}

String _resolvePackagePath(String pkgPath) {
  final normalized = pkgPath.endsWith('/') ? pkgPath : '$pkgPath/';
  return Directory.current.uri.resolve(normalized).toFilePath();
}

String _basename(String path) {
  final parts = path.split(RegExp(r'[\\/]+')).where((part) => part.isNotEmpty);
  return parts.isEmpty ? path : parts.last;
}

Future<String?> _resolveBaselineRef() async {
  final result = await Process.run('git', ['describe', '--tags', '--abbrev=0']);
  if (result.exitCode != 0) {
    return null;
  }
  final tag = (result.stdout as String).trim();
  return tag.isEmpty ? null : tag;
}

Future<bool> _packageChangedSince(String pkgPath, String? baselineRef) async {
  if (baselineRef == null) return true;
  final result = await Process.run('git', [
    'diff',
    '--name-only',
    '$baselineRef...HEAD',
    '--',
    pkgPath,
  ]);
  if (result.exitCode != 0) {
    final stderr = (result.stderr as String).trim();
    throw Exception(
      'Failed to detect changes for $pkgPath: '
      '${stderr.isEmpty ? 'git diff failed' : stderr}',
    );
  }
  final output = (result.stdout as String).trim();
  return output.isNotEmpty;
}

_PubspecInfo _readPubspec(File pubspecFile) {
  final namePattern = RegExp(r'^name:\s*(.+)$');
  final versionPattern = RegExp(r'^version:\s*(.+)$');
  String? name;
  String? version;
  for (final rawLine in pubspecFile.readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    final nameMatch = namePattern.firstMatch(line);
    if (nameMatch != null) {
      name = _stripQuotes(nameMatch.group(1));
      continue;
    }
    final versionMatch = versionPattern.firstMatch(line);
    if (versionMatch != null) {
      version = _stripQuotes(versionMatch.group(1));
    }
  }
  return _PubspecInfo(name: name, version: version);
}

String? _stripQuotes(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.length >= 2) {
    final start = trimmed[0];
    final end = trimmed[trimmed.length - 1];
    if ((start == '"' && end == '"') || (start == '\'' && end == '\'')) {
      return trimmed.substring(1, trimmed.length - 1);
    }
  }
  return trimmed;
}

Future<bool> _isVersionPublished(String packageName, String version) async {
  final info = await _fetchPubPackageInfo(packageName);
  if (info == null) return false;
  return info.versions.contains(version);
}

Future<_PubPackageInfo?> _fetchPubPackageInfo(String packageName) async {
  final client = HttpClient();
  try {
    final uri = Uri.https('pub.dev', '/api/packages/$packageName');
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      return null;
    }
    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final versions = <String>{};
    final versionEntries = decoded['versions'];
    if (versionEntries is List) {
      for (final entry in versionEntries) {
        if (entry is Map<String, dynamic>) {
          final version = entry['version'];
          if (version is String) {
            versions.add(version);
          }
        }
      }
    }
    final latest = decoded['latest'];
    String? latestVersion;
    if (latest is Map<String, dynamic>) {
      final latestValue = latest['version'];
      if (latestValue is String) {
        latestVersion = latestValue;
      }
    }
    return _PubPackageInfo(latestVersion, versions);
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

class _PubspecInfo {
  const _PubspecInfo({required this.name, required this.version});

  final String? name;
  final String? version;
}

class _PubPackageInfo {
  const _PubPackageInfo(this.latestVersion, this.versions);

  final String? latestVersion;
  final Set<String> versions;
}
