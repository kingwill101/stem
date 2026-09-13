// Copyright (c) 2025 Glenford Williams <hey@glenfordwilliams.com>
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:yaml/yaml.dart';

/// Validates package-distributed skills after workspace dependency resolution.
///
/// Run from the repository root:
///   dart run tool/validate_package_skills.dart
void main() {
  final root = Directory('packages');
  if (!root.existsSync()) {
    stderr.writeln('packages/ does not exist');
    exitCode = 1;
    return;
  }

  final errors = <String>[];
  for (final package in root.listSync().whereType<Directory>()) {
    final pubspec = File('${package.path}/pubspec.yaml');
    final skills = Directory('${package.path}/skills');
    if (!pubspec.existsSync() || !skills.existsSync()) continue;
    final packageData = loadYaml(pubspec.readAsStringSync());
    final packageName = packageData is YamlMap ? packageData['name'] : null;
    if (packageName is! String || packageName.isEmpty) {
      errors.add('${package.path}: pubspec has no name');
      continue;
    }
    final prefix = '$packageName-';
    for (final skill in skills.listSync().whereType<Directory>()) {
      final name = skill.uri.pathSegments.lastWhere(
        (segment) => segment.isNotEmpty,
        orElse: () => '',
      );
      final file = File('${skill.path}/SKILL.md');
      if (!name.startsWith(prefix) &&
          !name.startsWith('${packageName.replaceAll('_', '-')}-')) {
        errors.add('${skill.path}: directory must start with $prefix');
      }
      if (!file.existsSync()) {
        errors.add('${skill.path}: missing SKILL.md');
        continue;
      }
      final content = file.readAsStringSync();
      if (!content.startsWith('---\n') ||
          !RegExp(r'\n---\n').hasMatch(content.substring(4))) {
        errors.add('${file.path}: missing YAML frontmatter');
      } else {
        final header = content.substring(4, content.indexOf('\n---\n', 4));
        try {
          final metadata = loadYaml(header);
          final frontName = metadata is YamlMap ? metadata['name'] : null;
          final description = metadata is YamlMap
              ? metadata['description']
              : null;
          if (frontName != name) {
            errors.add(
              '${file.path}: frontmatter name is $frontName, expected $name',
            );
          }
          if (description is! String || description.trim().isEmpty) {
            errors.add('${file.path}: frontmatter description is empty');
          }
        } on YamlException catch (error) {
          errors.add('${file.path}: invalid YAML: ${error.message}');
        }
      }
      if (content.contains('../') || content.contains('..\\')) {
        errors.add('${file.path}: parent-relative reference is not portable');
      }
      if (content.split('\n').length > 500) {
        errors.add('${file.path}: SKILL.md exceeds 500 lines');
      }
    }
  }
  if (errors.isNotEmpty) {
    stderr.writeAll(errors.map((error) => 'ERROR: $error\n'));
    exitCode = 1;
  } else {
    stdout.writeln(
      'Package skill format, naming, and portability checks passed.',
    );
  }
}
