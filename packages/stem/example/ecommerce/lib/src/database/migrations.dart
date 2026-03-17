import 'dart:convert';

import 'package:ormed/migrations.dart';

import 'migrations/m_20260226010000_create_ecommerce_tables.dart';

final List<MigrationEntry> _entries = [
  MigrationEntry(
    id: MigrationId(
      DateTime.utc(2026, 2, 26, 1),
      'm_20260226010000_create_ecommerce_tables',
    ),
    migration: const CreateEcommerceTables(),
  ),
];

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
    print(jsonEncode(payload));
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
    print(jsonEncode(plan.toJson()));
  }
}
