import 'dart:convert';
import 'dart:io';

import 'package:ormed/migrations.dart';

import 'package:stem_sqlite/src/database/migrations/m_20251222070816_create_stem_tables.dart';
import 'package:stem_sqlite/src/database/migrations/m_20251231120000_create_workflow_tables.dart';
import 'package:stem_sqlite/src/database/migrations/m_20251231161000_add_namespace_scoping.dart';

final List<MigrationEntry> _entries = [
  MigrationEntry(
    id: MigrationId(
      DateTime.utc(2025, 12, 22, 7, 8, 16),
      'm_20251222070816_create_stem_tables',
    ),
    migration: const CreateStemTables(),
  ),
  MigrationEntry(
    id: MigrationId(
      DateTime.utc(2025, 12, 31, 12),
      'm_20251231120000_create_workflow_tables',
    ),
    migration: const CreateWorkflowTables(),
  ),
  MigrationEntry(
    id: MigrationId(
      DateTime.utc(2025, 12, 31, 16, 10),
      'm_20251231161000_add_namespace_scoping',
    ),
    migration: const AddNamespaceScoping(),
  ),
];

/// Build migration descriptors sorted by timestamp.
List<MigrationDescriptor> buildMigrations() =>
    MigrationEntry.buildDescriptors(_entries);

MigrationEntry? _findEntry(String rawId) {
  for (final entry in _entries) {
    if (entry.id.toString() == rawId) return entry;
  }
  return null;
}

void main(List<String> args) {
  if (args.contains('--dump-json')) {
    final payload = buildMigrations().map((m) => m.toJson()).toList();
    stdout.writeln(jsonEncode(payload));
    return;
  }

  final planIndex = args.indexOf('--plan-json');
  if (planIndex != -1) {
    final id = args[planIndex + 1];
    final entry = _findEntry(id);
    if (entry == null) {
      throw StateError('Unknown migration id $id.');
    }
    final directionName = args[args.indexOf('--direction') + 1];
    final direction = MigrationDirection.values.byName(directionName);
    final snapshotIndex = args.indexOf('--schema-snapshot');
    SchemaSnapshot? snapshot;
    if (snapshotIndex != -1) {
      final decoded = utf8.decode(base64.decode(args[snapshotIndex + 1]));
      final payload = jsonDecode(decoded) as Map<String, Object?>;
      snapshot = SchemaSnapshot.fromJson(payload);
    }
    final plan = entry.migration.plan(direction, snapshot: snapshot);
    stdout.writeln(jsonEncode(plan.toJson()));
  }
}
