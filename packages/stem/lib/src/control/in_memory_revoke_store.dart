import 'dart:async';

import 'package:collection/collection.dart';

import 'revoke_store.dart';

/// Simple in-memory implementation of [RevokeStore] useful for tests.
class InMemoryRevokeStore implements RevokeStore {
  final Map<String, Map<String, RevokeEntry>> _entries = {};

  @override
  Future<void> close() async {
    _entries.clear();
  }

  @override
  Future<List<RevokeEntry>> list(String namespace) async {
    final records = _entries[namespace];
    if (records == null || records.isEmpty) return const [];
    return records.values.sortedBy<num>((entry) => entry.version).toList();
  }

  @override
  Future<int> pruneExpired(String namespace, DateTime clock) async {
    final records = _entries[namespace];
    if (records == null || records.isEmpty) return 0;
    final toRemove = <String>[];
    records.forEach((key, value) {
      if (value.isExpired(clock)) {
        toRemove.add(key);
      }
    });
    for (final key in toRemove) {
      records.remove(key);
    }
    if (records.isEmpty) {
      _entries.remove(namespace);
    }
    return toRemove.length;
  }

  @override
  Future<List<RevokeEntry>> upsertAll(List<RevokeEntry> entries) async {
    final applied = <RevokeEntry>[];
    for (final entry in entries) {
      final namespaceRecords = _entries.putIfAbsent(
        entry.namespace,
        () => <String, RevokeEntry>{},
      );
      final current = namespaceRecords[entry.taskId];
      if (current == null || entry.version > current.version) {
        namespaceRecords[entry.taskId] = entry;
        applied.add(entry);
      } else {
        applied.add(current);
      }
    }
    return applied;
  }
}
