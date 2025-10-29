import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';

import 'revoke_store.dart';

/// File-based [RevokeStore] using newline-delimited JSON entries.
class FileRevokeStore implements RevokeStore {
  FileRevokeStore._(this._file, this._entries);

  final File _file;
  final Map<String, Map<String, RevokeEntry>> _entries;
  Future<void> _pending = Future<void>.value();

  /// Opens or creates a file-backed revoke store at [path].
  static Future<FileRevokeStore> open(String path) async {
    final file = File(path);
    final entries = <String, Map<String, RevokeEntry>>{};

    if (await file.exists()) {
      final lines = await file.readAsLines();
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final decoded = RevokeEntry.fromJson(
          (jsonDecode(line) as Map).cast<String, Object?>(),
        );
        entries.putIfAbsent(
          decoded.namespace,
          () => <String, RevokeEntry>{},
        )[decoded.taskId] = decoded;
      }
    } else {
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      await file.create();
    }

    return FileRevokeStore._(file, entries);
  }

  @override
  Future<void> close() async {}

  @override
  Future<List<RevokeEntry>> list(String namespace) async {
    return _entries[namespace]?.values
            .sortedBy<num>((entry) => entry.version)
            .toList() ??
        const [];
  }

  @override
  Future<int> pruneExpired(String namespace, DateTime clock) {
    return _synchronized(() async {
      final records = _entries[namespace];
      if (records == null || records.isEmpty) return 0;
      final toRemove = records.entries
          .where((entry) => entry.value.isExpired(clock))
          .map((entry) => entry.key)
          .toList();
      for (final key in toRemove) {
        records.remove(key);
      }
      if (records.isEmpty) {
        _entries.remove(namespace);
      }
      if (toRemove.isNotEmpty) {
        await _persistLocked();
      }
      return toRemove.length;
    });
  }

  @override
  Future<List<RevokeEntry>> upsertAll(List<RevokeEntry> entries) {
    return _synchronized(() async {
      final applied = <RevokeEntry>[];
      for (final entry in entries) {
        final map = _entries.putIfAbsent(
          entry.namespace,
          () => <String, RevokeEntry>{},
        );
        final current = map[entry.taskId];
        if (current == null || entry.version > current.version) {
          map[entry.taskId] = entry;
          applied.add(entry);
        } else {
          applied.add(current);
        }
      }
      if (entries.isNotEmpty) {
        await _persistLocked();
      }
      return applied;
    });
  }

  Future<T> _synchronized<T>(FutureOr<T> Function() action) {
    final completer = Completer<T>();
    _pending = _pending.then((_) async {
      try {
        final result = await action();
        completer.complete(result);
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<void> _persistLocked() async {
    final buffer = StringBuffer();
    for (final namespace in _entries.keys.sorted()) {
      final values = _entries[namespace]!;
      for (final entry in values.values.sortedBy<num>((e) => e.version)) {
        buffer.writeln(jsonEncode(entry.toJson()));
      }
    }

    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(buffer.toString());
    await tmp.rename(_file.path);
  }
}
