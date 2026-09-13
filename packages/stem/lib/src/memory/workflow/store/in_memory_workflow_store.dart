// This package depends on Stem's core internals while avoiding `stem.dart`
// import cycles created by the compatibility re-exports.
import 'dart:async';
import 'dart:collection';

import 'package:stem/src/workflow/core/run_state.dart';
import 'package:stem/src/workflow/core/workflow_cancellation_policy.dart';
import 'package:stem/src/workflow/core/workflow_clock.dart';
import 'package:stem/src/workflow/core/workflow_journal.dart';
import 'package:stem/src/workflow/core/workflow_status.dart';
import 'package:stem/src/workflow/core/workflow_step_entry.dart';
import 'package:stem/src/workflow/core/workflow_store.dart';
import 'package:stem/src/workflow/core/workflow_watcher.dart';

/// Simple in-memory [WorkflowStore] used for tests and examples.
///
/// Not safe for production as state is lost on process exit.
class InMemoryWorkflowStore
    implements
        WorkflowStore,
        WorkflowRunChanges,
        FencedWorkflowStore,
        WorkflowTerminalStore,
        WorkflowJournalStore {
  /// Creates an in-memory workflow store using the provided [clock].
  InMemoryWorkflowStore({WorkflowClock clock = const SystemWorkflowClock()})
    : _clock = clock;

  final WorkflowClock _clock;
  late final _ObservableRuns _runs = _ObservableRuns(_notifyRunChanged);
  final _runChangeControllers = <String, StreamController<void>>{};
  final _steps = <String, Map<String, Object?>>{};
  final _suspendedTopics = <String, Set<String>>{};
  final _due = SplayTreeMap<DateTime, Set<String>>();
  final _watchersByTopic = <String, LinkedHashMap<String, _WatcherRecord>>{};
  final _watchersByRun = <String, _WatcherRecord>{};
  int _counter = 0;
  int _executionCounter = 0;
  final _journal =
      <String, Map<(WorkflowJournalKind, String), WorkflowJournalEntry>>{};
  final _journalOrder = <String, int>{};

  @override
  Stream<void> watchRunChanges(String runId) => Stream<void>.multi((listener) {
    final controller = _runChangeControllers.putIfAbsent(
      runId,
      StreamController<void>.broadcast,
    );
    final subscription = controller.stream.listen(
      listener.add,
      onError: listener.addError,
      onDone: () => unawaited(listener.close()),
    );
    listener.onCancel = () async {
      await subscription.cancel();
      if (!controller.hasListener &&
          identical(_runChangeControllers[runId], controller)) {
        _runChangeControllers.remove(runId);
        await controller.close();
      }
    };
  });

  void _notifyRunChanged(String runId) {
    final controller = _runChangeControllers[runId];
    if (controller != null && !controller.isClosed) {
      controller.add(null);
    }
  }

  @override
  Future<WorkflowJournalSnapshot?> readJournal(
    String runId,
    WorkflowJournalKind kind,
    String name,
  ) async {
    final run = _readRunState(runId);
    if (run == null) return null;
    return WorkflowJournalSnapshot(
      run: run,
      entry: _journal[runId]?[(kind, name)],
    );
  }

  @override
  Future<List<WorkflowJournalEntry>> listCompensations(String runId) async {
    final entries =
        (_journal[runId]?.values
                  .where(
                    (entry) => entry.kind == WorkflowJournalKind.compensation,
                  )
                  .toList() ??
              <WorkflowJournalEntry>[])
          ..sort((a, b) => b.position!.compareTo(a.position!));
    return List.unmodifiable(entries);
  }

  @override
  Future<bool> commitJournal(
    WorkflowJournalEntry entry, {
    required int expectedRevision,
    required String executionId,
    WorkflowJournalCheckpoint? checkpoint,
  }) async {
    entry.validateWrite(
      expectedRevision: expectedRevision,
      checkpoint: checkpoint,
    );
    final run = _runs[entry.runId];
    final requiredStatus = entry.kind == WorkflowJournalKind.step
        ? WorkflowStatus.running
        : WorkflowStatus.failed;
    if (run == null ||
        run.status != requiredStatus ||
        run.executionId != executionId ||
        executionId.isEmpty) {
      return false;
    }
    final key = (entry.kind, entry.name);
    final records = _journal[entry.runId];
    final previous = records?[key];
    if ((previous?.revision ?? 0) != expectedRevision ||
        (entry.kind == WorkflowJournalKind.compensation && previous == null)) {
      return false;
    }
    // Validate/copy before publishing any part of the atomic mutation.
    final data = _copyJournalValue(entry.data)! as Map<String, Object?>;
    final value = _copyJournalValue(checkpoint?.value);
    final registration = checkpoint?.compensation;
    final registrationData = registration == null
        ? null
        : _copyJournalValue(registration.toJournalData())!
              as Map<String, Object?>;
    final target = _journal.putIfAbsent(entry.runId, () => {});
    target[key] = WorkflowJournalEntry(
      runId: entry.runId,
      kind: entry.kind,
      name: entry.name,
      revision: entry.revision,
      data: data,
      position: previous?.position,
    );
    if (checkpoint != null) {
      _steps.putIfAbsent(entry.runId, () => {})[entry.name] = value;
      final compensationKey = (WorkflowJournalKind.compensation, entry.name);
      if (registrationData != null && !target.containsKey(compensationKey)) {
        final position = (_journalOrder[entry.runId] ?? 0) + 1;
        _journalOrder[entry.runId] = position;
        target[compensationKey] = WorkflowJournalEntry(
          runId: entry.runId,
          kind: WorkflowJournalKind.compensation,
          name: entry.name,
          revision: 1,
          position: position,
          data: registrationData,
        );
      }
    }
    _runs[entry.runId] = run.copyWith(updatedAt: _clock.now());
    return true;
  }

  static Object? _copyJournalValue(Object? value) {
    if (value is Map<String, Object?>) {
      return Map<String, Object?>.unmodifiable(
        value.map((key, item) => MapEntry(key, _copyJournalValue(item))),
      );
    }
    if (value is List) {
      return List<Object?>.unmodifiable(value.map(_copyJournalValue));
    }
    return value;
  }

  Map<String, Object?> _prepareSuspensionData(
    Map<String, Object?>? source, {
    DateTime? resumeAt,
    DateTime? deadline,
    String? topic,
  }) {
    final result = <String, Object?>{};
    if (source != null) {
      result.addAll(source);
    }
    if (resumeAt != null && !result.containsKey('resumeAt')) {
      result['resumeAt'] = resumeAt.toIso8601String();
    }
    if (deadline != null && !result.containsKey('deadline')) {
      result['deadline'] = deadline.toIso8601String();
    }
    if (topic != null && topic.isNotEmpty && !result.containsKey('topic')) {
      result['topic'] = topic;
    }
    return Map.unmodifiable(result);
  }

  /// Returns an unmodifiable copy of stored metadata.
  Map<String, Object?> _freeze(Map<String, Object?> data) =>
      Map.unmodifiable(Map<String, Object?>.from(data));

  /// Freezes optional metadata to prevent accidental mutation.
  Map<String, Object?>? _freezeNullable(Map<String, Object?>? data) =>
      data == null ? null : _freeze(data);

  /// Strips iteration suffixes from step names (e.g., `step#2` -> `step`).
  String _baseStepName(String name) {
    final index = name.indexOf('#');
    if (index == -1) return name;
    return name.substring(0, index);
  }

  /// Returns true when a run lease is missing or has expired.
  bool _leaseExpired(RunState state, DateTime now) {
    final expiresAt = state.leaseExpiresAt;
    if (expiresAt == null) return true;
    return !expiresAt.isAfter(now);
  }

  /// Removes watcher bookkeeping for a run across run/topic maps.
  void _removeWatcherForRun(String runId) {
    final record = _watchersByRun.remove(runId);
    final topics = <String>{
      if (record != null) record.topic,
      if (_runs[runId]?.waitTopic case final String topic) topic,
    };
    for (final topic in topics) {
      final topicMap = _watchersByTopic[topic];
      topicMap?.remove(runId);
      if (topicMap != null && topicMap.isEmpty) {
        _watchersByTopic.remove(topic);
      }
      final suspended = _suspendedTopics[topic];
      suspended?.remove(runId);
      if (suspended != null && suspended.isEmpty) {
        _suspendedTopics.remove(topic);
      }
    }
  }

  @override
  /// Creates a new workflow run and returns its generated id.
  Future<String> createRun({
    required String workflow,
    required Map<String, Object?> params,
    String? runId,
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) async {
    final now = _clock.now();
    final id = (runId != null && runId.trim().isNotEmpty)
        ? runId.trim()
        : 'wf-${now.microsecondsSinceEpoch}-${_counter++}';
    if (_runs.containsKey(id)) {
      throw StateError('Workflow run "$id" already exists.');
    }
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
  /// Returns the run state with an updated step cursor, if present.
  Future<RunState?> get(String runId) async => _readRunState(runId);

  RunState? _readRunState(String runId) {
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
  /// Reads a stored step value for the given run.
  Future<T?> readStep<T>(String runId, String stepName) async {
    final steps = _steps[runId];
    if (steps == null) return null;
    return steps[stepName] as T?;
  }

  @override
  /// Persists a step value and updates the run timestamp.
  Future<void> saveStep<T>(String runId, String stepName, T value) async {
    _steps[runId]?[stepName] = value;
    final state = _runs[runId];
    if (state != null) {
      _runs[runId] = state.copyWith(updatedAt: _clock.now());
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
    if (state == null || state.isTerminal) return;
    _runs[runId] = state.copyWith(
      status: WorkflowStatus.suspended,
      cursor: state.cursor,
      resumeAt: when,
      suspensionData: _prepareSuspensionData(data, resumeAt: when),
      waitTopic: null,
      updatedAt: _clock.now(),
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
    _suspendOnTopic(
      runId,
      stepName,
      topic,
      deadline: deadline,
      data: data,
    );
  }

  bool _suspendOnTopic(
    String runId,
    String stepName,
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
  }) {
    final state = _runs[runId];
    if (state == null || state.isTerminal) return false;
    final metadata = _prepareSuspensionData(
      data,
      resumeAt: deadline,
      deadline: deadline,
      topic: topic,
    );
    _runs[runId] = state.copyWith(
      status: WorkflowStatus.suspended,
      waitTopic: topic,
      resumeAt: deadline,
      suspensionData: metadata,
      updatedAt: _clock.now(),
    );
    _suspendedTopics.putIfAbsent(topic, () => <String>{}).add(runId);
    if (deadline != null) {
      _due.putIfAbsent(deadline, () => <String>{}).add(runId);
    }
    return true;
  }

  @override
  Future<void> registerWatcher(
    String runId,
    String stepName,
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
  }) async {
    final metadata = _prepareSuspensionData(
      data,
      resumeAt: deadline,
      deadline: deadline,
      topic: topic,
    );
    if (!_suspendOnTopic(
      runId,
      stepName,
      topic,
      deadline: deadline,
      data: metadata,
    )) {
      return;
    }
    final record = _WatcherRecord(
      runId: runId,
      stepName: stepName,
      topic: topic,
      createdAt: _clock.now(),
      deadline: deadline,
      data: metadata,
    );
    final topicMap = _watchersByTopic.putIfAbsent(topic, LinkedHashMap.new);
    topicMap[runId] = record;
    _watchersByRun[runId] = record;
  }

  @override
  /// Marks a run as actively executing at [stepName].
  Future<void> markRunning(String runId, {String? stepName}) async {
    final state = _runs[runId];
    if (state == null || state.isTerminal) return;
    _removeWatcherForRun(runId);
    _runs[runId] = state.copyWith(
      status: WorkflowStatus.running,
      updatedAt: _clock.now(),
    );
  }

  @override
  /// Marks a run as completed and stores the final result.
  Future<void> markCompleted(String runId, Object? result) async {
    await completeIfActive(runId, result);
  }

  @override
  Future<bool> completeIfActive(String runId, Object? result) async {
    final state = _runs[runId];
    if (state == null || state.isTerminal) return false;
    _removeWatcherForRun(runId);
    _runs[runId] = state.copyWith(
      status: WorkflowStatus.completed,
      result: result,
      resumeAt: null,
      waitTopic: null,
      suspensionData: const <String, Object?>{},
      ownerId: null,
      leaseExpiresAt: null,
      updatedAt: _clock.now(),
    );
    for (final entry in _due.values) {
      entry.remove(runId);
    }
    return true;
  }

  @override
  Future<void> markFailed(
    String runId,
    Object error,
    StackTrace stack, {
    bool terminal = false,
  }) async {
    final state = _runs[runId];
    if (state == null || state.isTerminal) return;
    if (terminal) {
      _removeWatcherForRun(runId);
      for (final entry in _due.values) {
        entry.remove(runId);
      }
    }
    _runs[runId] = state.copyWith(
      status: terminal ? WorkflowStatus.failed : WorkflowStatus.running,
      lastError: {'error': error.toString(), 'stack': stack.toString()},
      resumeAt: terminal ? null : state.resumeAt,
      waitTopic: terminal ? null : state.waitTopic,
      suspensionData: terminal
          ? const <String, Object?>{}
          : state.suspensionData,
      ownerId: terminal ? null : state.ownerId,
      leaseExpiresAt: terminal ? null : state.leaseExpiresAt,
      updatedAt: _clock.now(),
    );
  }

  @override
  /// Marks a run as resumed, optionally merging resume data.
  Future<void> markResumed(String runId, {Map<String, Object?>? data}) async {
    final state = _runs[runId];
    if (state == null || state.isTerminal) return;
    _removeWatcherForRun(runId);
    _runs[runId] = state.copyWith(
      status: WorkflowStatus.running,
      resumeAt: null,
      waitTopic: null,
      suspensionData: _freezeNullable(data) ?? const <String, Object?>{},
      executionId: null,
      ownerId: null,
      leaseExpiresAt: null,
      updatedAt: _clock.now(),
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
    emptyTopics.forEach(_suspendedTopics.remove);
  }

  @override
  /// Returns run ids that are due to execute at [now].
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
    toRemove.forEach(_due.remove);
    return ids;
  }

  @override
  Future<bool> claimRun(
    String runId, {
    required String ownerId,
    Duration leaseDuration = const Duration(seconds: 30),
  }) async {
    final state = _runs[runId];
    if (state == null) return false;
    if (state.status != WorkflowStatus.running) return false;
    if (state.waitTopic != null) return false;
    final now = _clock.now();
    if (state.executionId != null && !_leaseExpired(state, now)) return false;
    final currentOwner = state.ownerId;
    if (currentOwner != null &&
        currentOwner.isNotEmpty &&
        currentOwner != ownerId &&
        !_leaseExpired(state, now)) {
      return false;
    }
    _runs[runId] = state.copyWith(
      ownerId: ownerId,
      executionId: null,
      leaseExpiresAt: now.add(leaseDuration),
      updatedAt: now,
    );
    return true;
  }

  @override
  Future<WorkflowExecutionClaim?> claimRunExecution(
    String runId, {
    required String ownerId,
    Duration leaseDuration = const Duration(seconds: 30),
  }) async {
    final state = _runs[runId];
    if (state == null || state.status != WorkflowStatus.running) return null;
    if (state.waitTopic != null) return null;
    final now = _clock.now();
    if (!_leaseExpired(state, now)) return null;
    final executionId = 'exec-${_executionCounter++}';
    final expiresAt = now.add(leaseDuration);
    _runs[runId] = state.copyWith(
      ownerId: ownerId,
      executionId: executionId,
      leaseExpiresAt: expiresAt,
      updatedAt: now,
    );
    return WorkflowExecutionClaim(
      runId: runId,
      executionId: executionId,
      ownerId: ownerId,
      leaseExpiresAt: expiresAt,
    );
  }

  @override
  Future<bool> renewRunExecution(
    String runId, {
    required String executionId,
    Duration leaseDuration = const Duration(seconds: 30),
  }) async {
    final state = _runs[runId];
    if (state == null ||
        state.status != WorkflowStatus.running ||
        state.executionId != executionId) {
      return false;
    }
    final now = _clock.now();
    if (state.ownerId == null || _leaseExpired(state, now)) return false;
    _runs[runId] = state.copyWith(
      leaseExpiresAt: now.add(leaseDuration),
      updatedAt: now,
    );
    return true;
  }

  @override
  Future<void> releaseRunExecution(
    String runId, {
    required String executionId,
  }) async {
    final state = _runs[runId];
    if (state == null || state.executionId != executionId) return;
    _runs[runId] = state.copyWith(
      ownerId: null,
      leaseExpiresAt: null,
      updatedAt: _clock.now(),
    );
  }

  @override
  Future<TerminalFailureResult> markFailedForExecution(
    String runId, {
    required String executionId,
    required Object error,
    required StackTrace stack,
    bool terminal = true,
  }) async {
    final state = _runs[runId];
    if (state == null || state.executionId != executionId) {
      return TerminalFailureResult.superseded;
    }
    if (state.status == WorkflowStatus.failed) {
      return TerminalFailureResult.alreadyFailedForExecution;
    }
    if (state.status == WorkflowStatus.completed ||
        state.status == WorkflowStatus.cancelled) {
      return TerminalFailureResult.superseded;
    }
    if (!terminal) {
      _runs[runId] = state.copyWith(
        lastError: {'error': error.toString(), 'stack': stack.toString()},
        updatedAt: _clock.now(),
      );
      return TerminalFailureResult.applied;
    }
    _removeWatcherForRun(runId);
    for (final due in _due.values) {
      due.remove(runId);
    }
    _runs[runId] = state.copyWith(
      status: WorkflowStatus.failed,
      lastError: {'error': error.toString(), 'stack': stack.toString()},
      ownerId: null,
      leaseExpiresAt: null,
      resumeAt: null,
      waitTopic: null,
      updatedAt: _clock.now(),
    );
    return TerminalFailureResult.applied;
  }

  @override
  Future<bool> renewRunLease(
    String runId, {
    required String ownerId,
    Duration leaseDuration = const Duration(seconds: 30),
  }) async {
    final state = _runs[runId];
    if (state == null) return false;
    if (state.status != WorkflowStatus.running) return false;
    if (state.executionId != null) return false;
    if (state.ownerId != ownerId) return false;
    final now = _clock.now();
    _runs[runId] = state.copyWith(
      leaseExpiresAt: now.add(leaseDuration),
      updatedAt: now,
    );
    return true;
  }

  @override
  /// Releases the workflow run lease if the owner matches.
  Future<void> releaseRun(String runId, {required String ownerId}) async {
    final state = _runs[runId];
    if (state == null) return;
    if (state.executionId != null) return;
    if (state.ownerId != ownerId) return;
    _runs[runId] = state.copyWith(
      ownerId: null,
      leaseExpiresAt: null,
      updatedAt: _clock.now(),
    );
  }

  @override
  /// Lists runs waiting on a specific event [topic].
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
    final now = _clock.now();
    final ids = topicMap.keys.take(limit).toList(growable: false);
    final results = <WorkflowWatcherResolution>[];
    for (final runId in ids) {
      final record = topicMap.remove(runId);
      if (record == null) continue;
      _watchersByRun.remove(runId);
      final state = _runs[runId];
      if (state == null || state.isTerminal) {
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
      metadata
        ..putIfAbsent('step', () => record.stepName)
        ..putIfAbsent(
          'iterationStep',
          () => metadata['step'] ?? record.stepName,
        );
      metadata['deliveredAt'] = now.toIso8601String();
      _runs[runId] = state.copyWith(
        status: WorkflowStatus.running,
        waitTopic: null,
        resumeAt: null,
        suspensionData: _freeze(metadata),
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
  /// Cancels a run and records an optional cancellation [reason].
  Future<void> cancel(String runId, {String? reason}) async {
    await cancelIfActive(runId, reason: reason);
  }

  @override
  Future<bool> cancelIfActive(String runId, {String? reason}) async {
    final state = _runs[runId];
    if (state == null || state.isTerminal) return false;
    _removeWatcherForRun(runId);
    final now = _clock.now();
    final cancellationData = <String, Object?>{
      'reason': reason ?? 'cancelled',
      'cancelledAt': now.toIso8601String(),
    };
    _runs[runId] = state.copyWith(
      status: WorkflowStatus.cancelled,
      waitTopic: null,
      resumeAt: null,
      suspensionData: const <String, Object?>{},
      ownerId: null,
      leaseExpiresAt: null,
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
    emptyTopics.forEach(_suspendedTopics.remove);
    return true;
  }

  @override
  /// Rewinds a run to the specified [stepName].
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
        // Drop all iterations for the target step so the runtime restarts from
        // iteration 0.
        continue;
      } else {
        break;
      }
    }
    _steps[runId] = LinkedHashMap.fromEntries(retained);
    final retainedNames = retained.map((entry) => entry.key).toSet();
    _journal[runId]?.removeWhere(
      (_, entry) => !retainedNames.contains(entry.name),
    );
    _runs[runId] = state.copyWith(
      status: WorkflowStatus.suspended,
      cursor: targetIndex,
      executionId: null,
      ownerId: null,
      leaseExpiresAt: null,
      suspensionData: _freeze(<String, Object?>{
        'step': stepName,
        'iteration': 0,
        'iterationStep': stepName,
      }),
    );
  }

  @override
  /// Lists workflow runs ordered by creation time.
  Future<List<RunState>> listRuns({
    String? workflow,
    WorkflowStatus? status,
    int limit = 50,
    int offset = 0,
  }) async {
    final candidates = _runs.values.where((state) {
      if (workflow != null && state.workflow != workflow) return false;
      if (status != null && state.status != status) return false;
      return true;
    }).toList()..sort((a, b) => b.id.compareTo(a.id));
    final start = offset < 0 ? 0 : offset;
    final limited = candidates.skip(start).take(limit);
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
  /// Lists runnable runs, excluding those already leased.
  Future<List<String>> listRunnableRuns({
    DateTime? now,
    int limit = 50,
    int offset = 0,
  }) async {
    final resolvedNow = now ?? _clock.now();
    final candidates = _runs.values.where((state) {
      if (state.status != WorkflowStatus.running) return false;
      if (state.waitTopic != null) return false;
      if (!_leaseExpired(state, resolvedNow) &&
          state.ownerId != null &&
          state.ownerId!.isNotEmpty) {
        return false;
      }
      return true;
    }).toList()..sort((a, b) => b.id.compareTo(a.id));
    final start = offset < 0 ? 0 : offset;
    return candidates
        .skip(start)
        .take(limit)
        .map((state) => state.id)
        .toList(growable: false);
  }

  @override
  /// Lists stored step entries for a run.
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

/// A run map that makes every replacement/removal observable through one path.
class _ObservableRuns extends MapBase<String, RunState> {
  _ObservableRuns(this._onChange);

  final void Function(String runId) _onChange;
  final _values = <String, RunState>{};

  @override
  RunState? operator [](Object? key) => _values[key];

  @override
  void operator []=(String key, RunState value) {
    _values[key] = value;
    _onChange(key);
  }

  @override
  void clear() {
    final keys = _values.keys.toList(growable: false);
    _values.clear();
    keys.forEach(_onChange);
  }

  @override
  Iterable<String> get keys => _values.keys;

  @override
  RunState? remove(Object? key) {
    if (key is! String) return null;
    if (!_values.containsKey(key)) return null;
    final value = _values.remove(key)!;
    _onChange(key);
    return value;
  }
}

/// Internal record used to index workflow watchers by run and topic.
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
