import 'dart:collection';

import '../core/run_state.dart';
import '../core/workflow_status.dart';
import '../core/workflow_store.dart';
import '../core/workflow_step_entry.dart';

/// Simple in-memory [WorkflowStore] used for tests and examples.
///
/// Not safe for production as state is lost on process exit.
class InMemoryWorkflowStore implements WorkflowStore {
  final _runs = <String, RunState>{};
  final _steps = <String, Map<String, Object?>>{};
  final _suspendedTopics = <String, Set<String>>{};
  final _due = SplayTreeMap<DateTime, Set<String>>();
  int _counter = 0;

  Map<String, Object?>? _cloneData(Map<String, Object?>? source) {
    if (source == null) return null;
    return Map.unmodifiable(Map<String, Object?>.from(source));
  }

  @override
  Future<String> createRun({
    required String workflow,
    required Map<String, Object?> params,
    String? parentRunId,
    Duration? ttl,
  }) async {
    final id = 'wf-${DateTime.now().microsecondsSinceEpoch}-${_counter++}';
    _runs[id] = RunState(
      id: id,
      workflow: workflow,
      status: WorkflowStatus.running,
      cursor: 0,
      params: Map.unmodifiable(params),
      suspensionData: const <String, Object?>{},
    );
    _steps[id] = {};
    return id;
  }

  @override
  Future<RunState?> get(String runId) async {
    final state = _runs[runId];
    if (state == null) return null;
    final cursor = _steps[runId]?.length ?? 0;
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
    );
    _suspendedTopics.putIfAbsent(topic, () => <String>{}).add(runId);
    if (deadline != null) {
      _due.putIfAbsent(deadline, () => <String>{}).add(runId);
    }
  }

  @override
  Future<void> markRunning(String runId, {String? stepName}) async {
    final state = _runs[runId];
    if (state == null) return;
    _runs[runId] = state.copyWith(status: WorkflowStatus.running);
  }

  @override
  Future<void> markCompleted(String runId, Object? result) async {
    final state = _runs[runId];
    if (state == null) return;
    _runs[runId] = state.copyWith(
      status: WorkflowStatus.completed,
      result: result,
      resumeAt: null,
      waitTopic: null,
      suspensionData: const <String, Object?>{},
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
    _runs[runId] = state.copyWith(
      status: terminal ? WorkflowStatus.failed : WorkflowStatus.running,
      lastError: {'error': error.toString(), 'stack': stack.toString()},
    );
  }

  @override
  Future<void> markResumed(String runId, {Map<String, Object?>? data}) async {
    final state = _runs[runId];
    if (state == null) return;
    _runs[runId] = state.copyWith(
      status: WorkflowStatus.running,
      resumeAt: null,
      waitTopic: null,
      suspensionData: _cloneData(data),
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
    final runs = _suspendedTopics[topic];
    if (runs == null) return const [];
    return runs.take(limit).toList(growable: false);
  }

  @override
  Future<void> cancel(String runId, {String? reason}) async {
    final state = _runs[runId];
    if (state == null) return;
    _runs[runId] = state.copyWith(
      status: WorkflowStatus.cancelled,
      waitTopic: null,
      resumeAt: null,
      suspensionData: const <String, Object?>{},
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
    final keys = steps.keys.toList();
    final targetIndex = keys.indexOf(stepName);
    if (targetIndex == -1) {
      return;
    }
    final retained = steps.entries.where((entry) {
      final index = keys.indexOf(entry.key);
      return index < targetIndex;
    });
    _steps[runId] = Map.fromEntries(retained);
    _runs[runId] = state.copyWith(cursor: targetIndex);
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
      final cursor = _steps[state.id]?.length ?? 0;
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
