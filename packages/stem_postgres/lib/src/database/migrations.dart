import 'dart:convert';
import 'dart:io';

import 'package:ormed/migrations.dart';

// <ORM-MIGRATION-IMPORTS>
import 'package:stem_postgres/src/database/migrations/m_20251227071920_stem.dart';
import 'package:stem_postgres/src/database/migrations/m_20251231160000_add_namespace_scoping.dart';
import 'package:stem_postgres/src/database/migrations/m_20260116121000_add_workflow_run_leases.dart'; // </ORM-MIGRATION-IMPORTS>

final List<MigrationEntry> _entries = [
  // <ORM-MIGRATION-REGISTRY>
  MigrationEntry(
    id: MigrationId(DateTime(2025, 12, 27, 7, 19, 20), 'm_20251227071920_stem'),
    migration: const Stem(),
  ), // </ORM-MIGRATION-REGISTRY>
  MigrationEntry(
    id: MigrationId(
      DateTime(2025, 12, 31, 16),
      'm_20251231160000_add_namespace_scoping',
    ),
    migration: const AddNamespaceScoping(),
  ),
  MigrationEntry(
    id: MigrationId(
      DateTime(2026, 1, 16, 12, 10),
      'm_20260116121000_add_workflow_run_leases',
    ),
    migration: const AddWorkflowRunLeases(),
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
    return;
  }
}
