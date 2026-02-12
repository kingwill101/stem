import 'dart:async';

import 'package:stem/src/core/chord_metadata.dart';
import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/observability/heartbeat.dart';

/// Simple in-memory result backend used for tests and local development.
class InMemoryResultBackend implements ResultBackend {
  /// Creates an in-memory backend with configurable TTLs.
  InMemoryResultBackend({
    this.defaultTtl = const Duration(days: 1),
    this.groupDefaultTtl = const Duration(days: 1),
    this.heartbeatTtl = const Duration(seconds: 60),
  });

  /// Default expiration applied to task statuses.
  final Duration defaultTtl;

  /// Default expiration applied to group/chord metadata.
  final Duration groupDefaultTtl;

  /// Time-to-live applied to worker heartbeat entries.
  final Duration heartbeatTtl;

  /// Task status entries keyed by task id.
  final Map<String, _Entry> _entries = {};

  /// Per-task expiry timers used to evict stale entries.
  final Map<String, Timer> _expiryTimers = {};

  /// Active watchers keyed by task id.
  final Map<String, StreamController<TaskStatus>> _watchers = {};

  /// Group/chord state keyed by group id.
  final Map<String, _GroupEntry> _groups = {};

  /// Per-group expiry timers used to remove stale groups.
  final Map<String, Timer> _groupExpiry = {};

  /// Groups that have been claimed for chord dispatch.
  final Set<String> _claimedChords = {};

  /// Latest worker heartbeats keyed by worker id.
  final Map<String, _HeartbeatEntry> _heartbeats = {};

  /// Per-worker heartbeat expiry timers.
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
    final now = DateTime.now();
    final existing = _entries[taskId];
    final createdAt = existing?.createdAt ?? now;
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
      createdAt: createdAt,
      updatedAt: now,
    );

    _scheduleExpiry(taskId, ttl ?? defaultTtl);
    _watchers[taskId]?.add(status);
  }

  @override
  /// Returns the latest task status if still within its TTL.
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
  /// Watches updates for a task ID, emitting new statuses.
  Stream<TaskStatus> watch(String taskId) {
    final controller = _watchers.putIfAbsent(
      taskId,
      () => StreamController<TaskStatus>.broadcast(
        onCancel: () {
          if (!(_watchers[taskId]?.hasListener ?? false)) {
            final controller = _watchers.remove(taskId);
            if (controller != null) {
              unawaited(controller.close());
            }
          }
        },
      ),
    );
    return controller.stream;
  }

  @override
  Future<TaskStatusPage> listTaskStatuses(
    TaskStatusListRequest request,
  ) async {
    _pruneExpired();
    if (request.limit <= 0) {
      return const TaskStatusPage(items: []);
    }
    final matches = _entries.values.where((entry) {
      if (request.state != null && entry.status.state != request.state) {
        return false;
      }
      if (request.queue != null) {
        final queue = entry.status.meta['queue']?.toString();
        if (queue != request.queue) {
          return false;
        }
      }
      if (!_matchesMeta(entry.status.meta, request.meta)) {
        return false;
      }
      return true;
    }).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final offset = request.offset;
    final limit = request.limit;
    final pageItems = matches
        .skip(offset)
        .take(limit)
        .map((entry) {
          return TaskStatusRecord(
            status: entry.status,
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt,
          );
        })
        .toList(growable: false);
    final hasNext = matches.length > offset + limit;
    return TaskStatusPage(
      items: pageItems,
      nextOffset: hasNext ? offset + limit : null,
    );
  }

  @override
  /// Initializes a group/chord tracking entry.
  Future<void> initGroup(GroupDescriptor descriptor) async {
    _groups[descriptor.id] = _GroupEntry(
      descriptor: descriptor,
      expiresAt: DateTime.now().add(descriptor.ttl ?? groupDefaultTtl),
    );
    _claimedChords.remove(descriptor.id);
    _scheduleGroupExpiry(descriptor.id, descriptor.ttl ?? groupDefaultTtl);
  }

  @override
  /// Adds a result to a group, returning the updated aggregate.
  Future<GroupStatus?> addGroupResult(String groupId, TaskStatus status) async {
    final group = _groups[groupId];
    if (group == null) return null;
    group.results[status.id] = status;
    return GroupStatus(
      id: groupId,
      expected: group.descriptor.expected,
      results: Map.unmodifiable(group.results),
      meta: group.meta,
    );
  }

  @override
  /// Returns the group status if it has not expired.
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
      meta: group.meta,
    );
  }

  @override
  /// Extends the TTL for a task status entry.
  Future<void> expire(String taskId, Duration ttl) async {
    final entry = _entries[taskId];
    if (entry == null) return;
    entry.expiresAt = DateTime.now().add(ttl);
    _scheduleExpiry(taskId, ttl);
  }

  @override
  Future<bool> claimChord(
    String groupId, {
    String? callbackTaskId,
    DateTime? dispatchedAt,
  }) async {
    final added = _claimedChords.add(groupId);
    if (!added) {
      return false;
    }
    final group = _groups[groupId];
    if (group != null) {
      group.meta['stem.chord.claimed'] = true;
      if (callbackTaskId != null) {
        group.meta[ChordMetadata.callbackTaskId] = callbackTaskId;
      }
      if (dispatchedAt != null) {
        group.meta[ChordMetadata.dispatchedAt] = dispatchedAt.toIso8601String();
      }
    }
    return true;
  }

  @override
  /// Stores or refreshes a worker heartbeat entry.
  Future<void> setWorkerHeartbeat(WorkerHeartbeat heartbeat) async {
    final expiresAt = DateTime.now().add(heartbeatTtl);
    _heartbeats[heartbeat.workerId] = _HeartbeatEntry(
      heartbeat: heartbeat,
      expiresAt: expiresAt,
    );
    _scheduleHeartbeatExpiry(heartbeat.workerId, heartbeatTtl);
  }

  @override
  /// Retrieves a worker heartbeat if still within its TTL.
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
  /// Lists all non-expired worker heartbeats.
  Future<List<WorkerHeartbeat>> listWorkerHeartbeats() async {
    _pruneExpiredHeartbeats();
    return _heartbeats.values
        .map((entry) => entry.heartbeat)
        .toList(growable: false);
  }

  /// Starts or resets the expiry timer for a task status entry.
  void _scheduleExpiry(String key, Duration ttl) {
    _expiryTimers[key]?.cancel();
    _expiryTimers[key] = Timer(ttl, () => _remove(key));
  }

  /// Removes a task entry and any watchers associated with it.
  void _remove(String key) {
    _expiryTimers.remove(key)?.cancel();
    _entries.remove(key);
    final controller = _watchers.remove(key);
    if (controller != null) {
      unawaited(controller.close());
    }
  }

  /// Starts or resets the expiry timer for a group/chord entry.
  void _scheduleGroupExpiry(String key, Duration ttl) {
    _groupExpiry[key]?.cancel();
    _groupExpiry[key] = Timer(ttl, () => _removeGroup(key));
  }

  /// Removes a group entry and related chord bookkeeping.
  void _removeGroup(String key) {
    _groupExpiry.remove(key)?.cancel();
    _groups.remove(key);
    _claimedChords.remove(key);
  }

  /// Starts or resets the expiry timer for a worker heartbeat.
  void _scheduleHeartbeatExpiry(String key, Duration ttl) {
    _heartbeatExpiry[key]?.cancel();
    _heartbeatExpiry[key] = Timer(ttl, () => _removeHeartbeat(key));
  }

  /// Removes a worker heartbeat entry.
  void _removeHeartbeat(String key) {
    _heartbeatExpiry.remove(key)?.cancel();
    _heartbeats.remove(key);
  }

  /// Cancels timers and closes any active watchers.
  Future<void> dispose() async {
    for (final timer in _expiryTimers.values) {
      timer.cancel();
    }
    _expiryTimers.clear();
    for (final controller in _watchers.values) {
      await controller.close();
    }
    _watchers.clear();

    for (final timer in _groupExpiry.values) {
      timer.cancel();
    }
    _groupExpiry.clear();
    _groups.clear();
    _claimedChords.clear();

    for (final timer in _heartbeatExpiry.values) {
      timer.cancel();
    }
    _heartbeatExpiry.clear();
    _heartbeats.clear();
  }

  @override
  Future<void> close() => dispose();

  /// Evicts expired worker heartbeats before listing.
  void _pruneExpiredHeartbeats() {
    final now = DateTime.now();
    _heartbeats.entries
        .where((entry) => entry.value.expiresAt.isBefore(now))
        .map((entry) => entry.key)
        .toList(growable: false)
        .forEach(_removeHeartbeat);
  }

  /// Evicts expired task status entries before listing.
  void _pruneExpired() {
    final now = DateTime.now();
    _entries.entries
        .where((entry) => entry.value.expiresAt.isBefore(now))
        .map((entry) => entry.key)
        .toList(growable: false)
        .forEach(_remove);
  }

  /// Checks that all key/value pairs in [filters] match [meta].
  bool _matchesMeta(
    Map<String, Object?> meta,
    Map<String, Object?> filters,
  ) {
    if (filters.isEmpty) return true;
    for (final entry in filters.entries) {
      if (!meta.containsKey(entry.key)) return false;
      final expected = entry.value;
      if (expected == null) continue;
      if (meta[entry.key] != expected) return false;
    }
    return true;
  }
}

/// Internal record storing task status with timestamps.
class _Entry {
  _Entry({
    required this.status,
    required this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Task status snapshot.
  final TaskStatus status;

  /// Expiration timestamp for this entry.
  DateTime expiresAt;

  /// Timestamp when the entry was created.
  DateTime createdAt;

  /// Timestamp of the most recent update.
  DateTime updatedAt;
}

/// Internal record storing group/chord metadata and results.
class _GroupEntry {
  _GroupEntry({required this.descriptor, required this.expiresAt})
    : meta = Map<String, Object?>.from(descriptor.meta);

  /// Group descriptor for expected results and metadata.
  final GroupDescriptor descriptor;

  /// Mutable metadata for chord bookkeeping.
  final Map<String, Object?> meta;

  /// Results collected for each task in the group.
  final Map<String, TaskStatus> results = {};

  /// Expiration timestamp for the group.
  DateTime expiresAt;
}

/// Internal record storing worker heartbeat snapshots.
class _HeartbeatEntry {
  _HeartbeatEntry({required this.heartbeat, required this.expiresAt});

  /// Latest heartbeat snapshot.
  final WorkerHeartbeat heartbeat;

  /// Expiration timestamp for the heartbeat.
  DateTime expiresAt;
}
