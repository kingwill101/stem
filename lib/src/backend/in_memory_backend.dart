import 'dart:async';

import '../core/contracts.dart';
import '../observability/heartbeat.dart';

/// Simple in-memory result backend used for tests and local development.
class InMemoryResultBackend implements ResultBackend {
  InMemoryResultBackend({
    this.defaultTtl = const Duration(days: 1),
    this.groupDefaultTtl = const Duration(days: 1),
    this.heartbeatTtl = const Duration(seconds: 60),
  });

  final Duration defaultTtl;
  final Duration groupDefaultTtl;
  final Duration heartbeatTtl;

  final Map<String, _Entry> _entries = {};
  final Map<String, Timer> _expiryTimers = {};
  final Map<String, StreamController<TaskStatus>> _watchers = {};

  final Map<String, _GroupEntry> _groups = {};
  final Map<String, Timer> _groupExpiry = {};
  final Map<String, _HeartbeatEntry> _heartbeats = {};
  final Map<String, Timer> _heartbeatExpiry = {};

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

  @override
  Future<void> expire(String taskId, Duration ttl) async {
    final entry = _entries[taskId];
    if (entry == null) return;
    entry.expiresAt = DateTime.now().add(ttl);
    _scheduleExpiry(taskId, ttl);
  }

  @override
  Future<void> setWorkerHeartbeat(WorkerHeartbeat heartbeat) async {
    final expiresAt = DateTime.now().add(heartbeatTtl);
    _heartbeats[heartbeat.workerId] = _HeartbeatEntry(
      heartbeat: heartbeat,
      expiresAt: expiresAt,
    );
    _scheduleHeartbeatExpiry(heartbeat.workerId, heartbeatTtl);
  }

  @override
  Future<WorkerHeartbeat?> getWorkerHeartbeat(String workerId) async {
    final entry = _heartbeats[workerId];
    if (entry == null) return null;
    if (entry.expiresAt.isBefore(DateTime.now())) {
      _removeHeartbeat(workerId);
      return null;
    }
    return entry.heartbeat;
  }

  @override
  Future<List<WorkerHeartbeat>> listWorkerHeartbeats() async {
    _pruneExpiredHeartbeats();
    return _heartbeats.values
        .map((entry) => entry.heartbeat)
        .toList(growable: false);
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

  void _scheduleHeartbeatExpiry(String key, Duration ttl) {
    _heartbeatExpiry[key]?.cancel();
    _heartbeatExpiry[key] = Timer(ttl, () => _removeHeartbeat(key));
  }

  void _removeHeartbeat(String key) {
    _heartbeatExpiry.remove(key)?.cancel();
    _heartbeats.remove(key);
  }

  void _pruneExpiredHeartbeats() {
    final now = DateTime.now();
    final stale = _heartbeats.entries
        .where((entry) => entry.value.expiresAt.isBefore(now))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final key in stale) {
      _removeHeartbeat(key);
    }
  }
}

class _Entry {
  _Entry({required this.status, required this.expiresAt});

  final TaskStatus status;
  DateTime expiresAt;
}

class _GroupEntry {
  _GroupEntry({required this.descriptor, required this.expiresAt});

  final GroupDescriptor descriptor;
  final Map<String, TaskStatus> results = {};
  DateTime expiresAt;
}

class _HeartbeatEntry {
  _HeartbeatEntry({required this.heartbeat, required this.expiresAt});

  final WorkerHeartbeat heartbeat;
  DateTime expiresAt;
}
