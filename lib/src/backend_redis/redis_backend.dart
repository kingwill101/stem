import 'dart:async';

import '../core/contracts.dart';

class RedisResultBackend implements ResultBackend {
  RedisResultBackend({
    this.defaultTtl = const Duration(days: 1),
    this.groupDefaultTtl = const Duration(days: 1),
  });

  final Duration defaultTtl;
  final Duration groupDefaultTtl;

  final Map<String, _Entry> _entries = {};
  final Map<String, Timer> _expiryTimers = {};
  final Map<String, StreamController<TaskStatus>> _watchers = {};

  final Map<String, _GroupEntry> _groups = {};
  final Map<String, Timer> _groupExpiry = {};

  @override
  Future<void> set(
    String taskId,
    TaskState state, {
    Object? payload,
    TaskError? error,
    int attempt = 0,
    Map<String, Object?> meta = const {},
    Duration? ttl,
  }) async {
    final status = TaskStatus(
      id: taskId,
      state: state,
      payload: payload,
      error: error,
      attempt: attempt,
      meta: meta,
    );

    _entries[taskId] = _Entry(
      status: status,
      expiresAt: DateTime.now().add(ttl ?? defaultTtl),
    );

    _scheduleExpiry(taskId, ttl ?? defaultTtl);
    _watchers[taskId]?.add(status);
  }

  @override
  Future<TaskStatus?> get(String taskId) async {
    final entry = _entries[taskId];
    if (entry == null) return null;
    if (entry.expiresAt.isBefore(DateTime.now())) {
      _remove(taskId);
      return null;
    }
    return entry.status;
  }

  @override
  Stream<TaskStatus> watch(String taskId) {
    final controller = _watchers.putIfAbsent(
      taskId,
      () => StreamController<TaskStatus>.broadcast(
        onCancel: () {
          if (!(_watchers[taskId]?.hasListener ?? false)) {
            _watchers.remove(taskId)?.close();
          }
        },
      ),
    );
    return controller.stream;
  }

  @override
  Future<void> initGroup(GroupDescriptor descriptor) async {
    _groups[descriptor.id] = _GroupEntry(
      descriptor: descriptor,
      expiresAt: DateTime.now().add(descriptor.ttl ?? groupDefaultTtl),
    );
    _scheduleGroupExpiry(descriptor.id, descriptor.ttl ?? groupDefaultTtl);
  }

  @override
  Future<GroupStatus?> addGroupResult(String groupId, TaskStatus status) async {
    final group = _groups[groupId];
    if (group == null) return null;
    group.results[status.id] = status;
    return GroupStatus(
      id: groupId,
      expected: group.descriptor.expected,
      results: Map.unmodifiable(group.results),
      meta: group.descriptor.meta,
    );
  }

  @override
  Future<GroupStatus?> getGroup(String groupId) async {
    final group = _groups[groupId];
    if (group == null) return null;
    if (group.expiresAt.isBefore(DateTime.now())) {
      _removeGroup(groupId);
      return null;
    }
    return GroupStatus(
      id: groupId,
      expected: group.descriptor.expected,
      results: Map.unmodifiable(group.results),
      meta: group.descriptor.meta,
    );
  }

  void _scheduleExpiry(String key, Duration ttl) {
    _expiryTimers[key]?.cancel();
    _expiryTimers[key] = Timer(ttl, () => _remove(key));
  }

  void _remove(String key) {
    _expiryTimers.remove(key)?.cancel();
    _entries.remove(key);
    _watchers.remove(key)?.close();
  }

  void _scheduleGroupExpiry(String key, Duration ttl) {
    _groupExpiry[key]?.cancel();
    _groupExpiry[key] = Timer(ttl, () => _removeGroup(key));
  }

  void _removeGroup(String key) {
    _groupExpiry.remove(key)?.cancel();
    _groups.remove(key);
  }
}

class _Entry {
  _Entry({required this.status, required this.expiresAt});

  final TaskStatus status;
  final DateTime expiresAt;
}

class _GroupEntry {
  _GroupEntry({required this.descriptor, required this.expiresAt});

  final GroupDescriptor descriptor;
  final Map<String, TaskStatus> results = {};
  final DateTime expiresAt;
}
