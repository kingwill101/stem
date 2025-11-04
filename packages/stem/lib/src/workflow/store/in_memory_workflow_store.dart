import 'dart:collection';

import '../core/run_state.dart';
import '../core/workflow_cancellation_policy.dart';
import '../core/workflow_status.dart';
import '../core/workflow_store.dart';
import '../core/workflow_step_entry.dart';
import '../core/workflow_watcher.dart';

/// Simple in-memory [WorkflowStore] used for tests and examples.
///
/// Not safe for production as state is lost on process exit.
class InMemoryWorkflowStore implements WorkflowStore {
  final _runs = <String, RunState>{};
  final _steps = <String, Map<String, Object?>>{};
  final _suspendedTopics = <String, Set<String>>{};
  final _due = SplayTreeMap<DateTime, Set<String>>();
  final _watchersByTopic = <String, LinkedHashMap<String, _WatcherRecord>>{};
  final _watchersByRun = <String, _WatcherRecord>{};
  int _counter = 0;

  Map<String, Object?>? _cloneData(Map<String, Object?>? source) {
    if (source == null) return null;
    return Map.unmodifiable(Map<String, Object?>.from(source));
  }

  String _baseStepName(String name) {
    final index = name.indexOf('#');
    if (index == -1) return name;
    return name.substring(0, index);
  }

  void _removeWatcherForRun(String runId) {
    final record = _watchersByRun.remove(runId);
    if (record == null) return;
    final topicMap = _watchersByTopic[record.topic];
    topicMap?.remove(runId);
    if (topicMap != null && topicMap.isEmpty) {
      _watchersByTopic.remove(record.topic);
    }
    _suspendedTopics[record.topic]?.remove(runId);
  }

  @override
  Future<String> createRun({
    required String workflow,
    required Map<String, Object?> params,
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) async {
    final now = DateTime.now();
    final id = 'wf-${now.microsecondsSinceEpoch}-${_counter++}';
    _runs[id] = RunState(
      id: id,
      workflow: workflow,
      status: WorkflowStatus.running,
      cursor: 0,
      params: Map.unmodifiable(params),
      createdAt: now,
      updatedAt: now,
      suspensionData: const <String, Object?>{},
      cancellationPolicy: cancellationPolicy,
    );
    _steps[id] = {};
    return id;
  }

  @override
  Future<RunState?> get(String runId) async {
    final state = _runs[runId];
    if (state == null) return null;
    final steps = _steps[runId];
    var cursor = 0;
    if (steps != null) {
      final seen = <String>{};
      for (final name in steps.keys) {
        seen.add(_baseStepName(name));
      }
      cursor = seen.length;
    }
    return state.copyWith(cursor: cursor);
  }

  @override
  Future<T?> readStep<T>(String runId, String stepName) async {
    final steps = _steps[runId];
    if (steps == null) return null;
    return steps[stepName] as T?;
  }

  @override
  Future<void> saveStep<T>(String runId, String stepName, T value) async {
    _steps[runId]?[stepName] = value;
    final state = _runs[runId];
    if (state != null) {
      _runs[runId] = state.copyWith(updatedAt: DateTime.now());
    }
  }

  @override
  Future<void> suspendUntil(
    String runId,
    String stepName,
    DateTime when, {
    Map<String, Object?>? data,
  }) async {
    final state = _runs[runId];
    if (state == null) return;
    _runs[runId] = state.copyWith(
      status: WorkflowStatus.suspended,
      cursor: state.cursor,
      resumeAt: when,
      suspensionData: _cloneData(data),
      waitTopic: null,
      updatedAt: DateTime.now(),
    );
    _due.putIfAbsent(when, () => <String>{}).add(runId);
  }

  @override
  Future<void> suspendOnTopic(
    String runId,
    String stepName,
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
  }) async {
    final state = _runs[runId];
    if (state == null) return;
    _runs[runId] = state.copyWith(
      status: WorkflowStatus.suspended,
      waitTopic: topic,
      resumeAt: deadline,
      suspensionData: _cloneData(data),
      updatedAt: DateTime.now(),
    );
    _suspendedTopics.putIfAbsent(topic, () => <String>{}).add(runId);
    if (deadline != null) {
      _due.putIfAbsent(deadline, () => <String>{}).add(runId);
    }
  }

  @override
  Future<void> registerWatcher(
    String runId,
    String stepName,
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
  }) async {
    await suspendOnTopic(
      runId,
      stepName,
      topic,
      deadline: deadline,
      data: data,
    );
    final record = _WatcherRecord(
      runId: runId,
      stepName: stepName,
      topic: topic,
      createdAt: DateTime.now(),
      deadline: deadline,
      data: _cloneData(data) ?? const <String, Object?>{},
    );
    final topicMap = _watchersByTopic.putIfAbsent(topic, () => LinkedHashMap());
    topicMap[runId] = record;
    _watchersByRun[runId] = record;
  }

  @override
  Future<void> markRunning(String runId, {String? stepName}) async {
    final state = _runs[runId];
    if (state == null) return;
    _removeWatcherForRun(runId);
    _runs[runId] = state.copyWith(
      status: WorkflowStatus.running,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> markCompleted(String runId, Object? result) async {
    final state = _runs[runId];
    if (state == null) return;
    _removeWatcherForRun(runId);
    _runs[runId] = state.copyWith(
      status: WorkflowStatus.completed,
      result: result,
      resumeAt: null,
      waitTopic: null,
      suspensionData: const <String, Object?>{},
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> markFailed(
    String runId,
    Object error,
    StackTrace stack, {
    bool terminal = false,
  }) async {
    final state = _runs[runId];
    if (state == null) return;
    if (terminal) {
      _removeWatcherForRun(runId);
    }
    _runs[runId] = state.copyWith(
      status: terminal ? WorkflowStatus.failed : WorkflowStatus.running,
      lastError: {'error': error.toString(), 'stack': stack.toString()},
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> markResumed(String runId, {Map<String, Object?>? data}) async {
    final state = _runs[runId];
    if (state == null) return;
    _removeWatcherForRun(runId);
    _runs[runId] = state.copyWith(
      status: WorkflowStatus.running,
      resumeAt: null,
      waitTopic: null,
      suspensionData: _cloneData(data),
      updatedAt: DateTime.now(),
    );
    for (final entry in _due.values) {
      entry.remove(runId);
    }
    final emptyTopics = <String>[];
    _suspendedTopics.forEach((topic, set) {
      set.remove(runId);
      if (set.isEmpty) {
        emptyTopics.add(topic);
      }
    });
    for (final topic in emptyTopics) {
      _suspendedTopics.remove(topic);
    }
  }

  @override
  Future<List<String>> dueRuns(DateTime now, {int limit = 256}) async {
    final ids = <String>[];
    final toRemove = <DateTime>[];
    for (final entry in _due.entries) {
      if (entry.key.isAfter(now)) break;
      for (final runId in entry.value.toList()) {
        ids.add(runId);
        entry.value.remove(runId);
        if (ids.length >= limit) break;
      }
      if (entry.value.isEmpty) {
        toRemove.add(entry.key);
      }
      if (ids.length >= limit) break;
    }
    for (final key in toRemove) {
      _due.remove(key);
    }
    return ids;
  }

  @override
  Future<List<String>> runsWaitingOn(String topic, {int limit = 256}) async {
    final watchers = _watchersByTopic[topic];
    if (watchers != null && watchers.isNotEmpty) {
      return watchers.keys.take(limit).toList(growable: false);
    }
    final runs = _suspendedTopics[topic];
    if (runs == null) return const [];
    return runs.take(limit).toList(growable: false);
  }

  @override
  Future<List<WorkflowWatcherResolution>> resolveWatchers(
    String topic,
    Map<String, Object?> payload, {
    int limit = 256,
  }) async {
    final topicMap = _watchersByTopic[topic];
    if (topicMap == null || topicMap.isEmpty) return const [];
    final now = DateTime.now();
    final ids = topicMap.keys.take(limit).toList(growable: false);
    final results = <WorkflowWatcherResolution>[];
    for (final runId in ids) {
      final record = topicMap.remove(runId);
      if (record == null) continue;
      _watchersByRun.remove(runId);
      final state = _runs[runId];
      if (state == null) {
        final topicSet = _suspendedTopics[topic];
        topicSet?.remove(runId);
        if (topicSet != null && topicSet.isEmpty) {
          _suspendedTopics.remove(topic);
        }
        continue;
      }
      final metadata = Map<String, Object?>.from(record.data);
      metadata['type'] = 'event';
      metadata['topic'] = topic;
      metadata['payload'] = payload;
      metadata.putIfAbsent('step', () => record.stepName);
      metadata.putIfAbsent(
        'iterationStep',
        () => metadata['step'] ?? record.stepName,
      );
      metadata['deliveredAt'] = now.toIso8601String();
      _runs[runId] = state.copyWith(
        status: WorkflowStatus.running,
        waitTopic: null,
        resumeAt: null,
        suspensionData: _cloneData(metadata),
        updatedAt: now,
      );
      for (final entry in _due.values) {
        entry.remove(runId);
      }
      final topicSet = _suspendedTopics[topic];
      topicSet?.remove(runId);
      if (topicSet != null && topicSet.isEmpty) {
        _suspendedTopics.remove(topic);
      }
      results.add(
        WorkflowWatcherResolution(
          runId: runId,
          stepName: record.stepName,
          topic: topic,
          resumeData: metadata,
        ),
      );
    }
    if (topicMap.isEmpty) {
      _watchersByTopic.remove(topic);
    }
    return results;
  }

  @override
  Future<List<WorkflowWatcher>> listWatchers(
    String topic, {
    int limit = 256,
  }) async {
    final topicMap = _watchersByTopic[topic];
    if (topicMap == null || topicMap.isEmpty) return const [];
    final results = <WorkflowWatcher>[];
    for (final record in topicMap.values.take(limit)) {
      results.add(record.toWatcher());
    }
    return results;
  }

  @override
  Future<void> cancel(String runId, {String? reason}) async {
    final state = _runs[runId];
    if (state == null) return;
    _removeWatcherForRun(runId);
    final now = DateTime.now();
    final cancellationData = <String, Object?>{
      'reason': reason ?? 'cancelled',
      'cancelledAt': now.toIso8601String(),
    };
    _runs[runId] = state.copyWith(
      status: WorkflowStatus.cancelled,
      waitTopic: null,
      resumeAt: null,
      suspensionData: const <String, Object?>{},
      cancellationData: cancellationData,
      updatedAt: now,
    );
    for (final entry in _due.values) {
      entry.remove(runId);
    }
    final emptyTopics = <String>[];
    _suspendedTopics.forEach((topic, set) {
      set.remove(runId);
      if (set.isEmpty) {
        emptyTopics.add(topic);
      }
    });
    for (final topic in emptyTopics) {
      _suspendedTopics.remove(topic);
    }
  }

  @override
  Future<void> rewindToStep(String runId, String stepName) async {
    final steps = _steps[runId];
    if (steps == null) return;
    final state = _runs[runId];
    if (state == null) return;
    _removeWatcherForRun(runId);
    final entries = steps.entries.toList();
    final baseIndexMap = <String, int>{};
    var nextIndex = 0;
    final entryIndexes = <int>[];
    for (final entry in entries) {
      final base = _baseStepName(entry.key);
      baseIndexMap.putIfAbsent(base, () => nextIndex++);
      entryIndexes.add(baseIndexMap[base]!);
    }
    final targetIndex = baseIndexMap[stepName];
    if (targetIndex == null) {
      return;
    }
    final retained = <MapEntry<String, Object?>>[];
    for (var i = 0; i < entries.length; i++) {
      final baseIndex = entryIndexes[i];
      if (baseIndex < targetIndex) {
        retained.add(entries[i]);
      } else if (baseIndex == targetIndex) {
        // Drop all iterations for the target step so the runtime restarts from iteration 0.
        continue;
      } else {
        break;
      }
    }
    _steps[runId] = LinkedHashMap.fromEntries(retained);
    _runs[runId] = state.copyWith(
      status: WorkflowStatus.suspended,
      cursor: targetIndex,
      suspensionData: _cloneData(<String, Object?>{
        'step': stepName,
        'iteration': 0,
        'iterationStep': stepName,
      }),
    );
  }

  @override
  Future<List<RunState>> listRuns({
    String? workflow,
    WorkflowStatus? status,
    int limit = 50,
  }) async {
    final candidates = _runs.values.where((state) {
      if (workflow != null && state.workflow != workflow) return false;
      if (status != null && state.status != status) return false;
      return true;
    }).toList()..sort((a, b) => b.id.compareTo(a.id));
    final limited = candidates.take(limit);
    final results = <RunState>[];
    for (final state in limited) {
      final steps = _steps[state.id];
      var cursor = 0;
      if (steps != null) {
        final seen = <String>{};
        for (final name in steps.keys) {
          seen.add(_baseStepName(name));
        }
        cursor = seen.length;
      }
      results.add(state.copyWith(cursor: cursor));
    }
    return results;
  }

  @override
  Future<List<WorkflowStepEntry>> listSteps(String runId) async {
    final steps = _steps[runId];
    if (steps == null) return const [];
    final entries = <WorkflowStepEntry>[];
    var index = 0;
    for (final entry in steps.entries) {
      entries.add(
        WorkflowStepEntry(name: entry.key, value: entry.value, position: index),
      );
      index += 1;
    }
    return entries;
  }
}

class _WatcherRecord {
  _WatcherRecord({
    required this.runId,
    required this.stepName,
    required this.topic,
    required this.createdAt,
    this.deadline,
    Map<String, Object?> data = const {},
  }) : data = Map.unmodifiable(Map<String, Object?>.from(data));

  final String runId;
  final String stepName;
  final String topic;
  final DateTime createdAt;
  final DateTime? deadline;
  final Map<String, Object?> data;

  WorkflowWatcher toWatcher() => WorkflowWatcher(
    runId: runId,
    stepName: stepName,
    topic: topic,
    createdAt: createdAt,
    deadline: deadline,
    data: data,
  );
}
