import 'dart:convert';

import 'package:ormed/ormed.dart';
import 'package:stem/stem.dart';
import 'package:stem_postgres/src/connection.dart';
import 'package:stem_postgres/src/database/models/workflow_models.dart';
import 'package:uuid/uuid.dart';

/// PostgreSQL-backed [WorkflowStore] implementation using ormed ORM.
class PostgresWorkflowStore implements WorkflowStore {
  PostgresWorkflowStore._(
    this._connections, {
    required this.namespace,
    required WorkflowClock clock,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid(),
       _clock = clock;

  final PostgresConnections _connections;

  /// Namespace used to scope workflow resources.
  final String namespace;
  final Uuid _uuid;
  final WorkflowClock _clock;

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
    return result;
  }

  /// Connects to a PostgreSQL database and ensures workflow tables exist.
  static Future<PostgresWorkflowStore> connect(
    String uri, {
    String schema = 'public',
    String namespace = 'stem',
    String? applicationName,
    TlsConfig? tls,
    Uuid? uuid,
    WorkflowClock clock = const SystemWorkflowClock(),
  }) async {
    final resolvedNamespace = namespace.trim().isEmpty
        ? 'stem'
        : namespace.trim();
    final connections = await PostgresConnections.open(connectionString: uri);
    return PostgresWorkflowStore._(
      connections,
      namespace: resolvedNamespace,
      clock: clock,
      uuid: uuid,
    );
  }

  /// Closes the workflow store and releases database resources.
  Future<void> close() async {
    await _connections.close();
  }

  @override
  Future<String> createRun({
    required String workflow,
    required Map<String, Object?> params,
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) async {
    final id = _uuid.v7();
    final now = _clock.now().toUtc();

    await _connections.runInTransaction((ctx) async {
      final run = StemWorkflowRunInsertDto(
        id: id,
        namespace: namespace,
        workflow: workflow,
        status: WorkflowStatus.running.name,
        params: jsonEncode(params),
        cancellationPolicy: cancellationPolicy == null
            ? null
            : jsonEncode(cancellationPolicy.toJson()),
        createdAt: now,
        updatedAt: now,
      );

      await ctx.repository<StemWorkflowRun>().insert(run);
    });

    return id;
  }

  @override
  Future<RunState?> get(String runId) async {
    return _readRunState(_connections.context, runId);
  }

  Future<RunState?> _readRunState(QueryContext ctx, String runId) async {
    final run = await ctx
        .query<StemWorkflowRun>()
        .whereEquals('id', runId)
        .whereEquals('namespace', namespace)
        .first();

    if (run == null) return null;

    // Count distinct base step names for cursor
    final steps = await ctx
        .query<StemWorkflowStep>()
        .whereEquals('runId', runId)
        .whereEquals('namespace', namespace)
        .get();

    final baseSteps = <String>{};
    for (final step in steps) {
      baseSteps.add(_baseStepName(step.name));
    }

    return RunState(
      id: run.id,
      workflow: run.workflow,
      status: WorkflowStatus.values.firstWhere(
        (v) => v.name == run.status,
        orElse: () => WorkflowStatus.running,
      ),
      cursor: baseSteps.length,
      params: _decodeMap(run.params),
      result: _decodeValue(run.result),
      waitTopic: run.waitTopic,
      resumeAt: run.resumeAt,
      lastError: _decodeMap(run.lastError),
      suspensionData: _decodeMap(run.suspensionData),
      createdAt: run.createdAt,
      updatedAt: run.updatedAt,
      cancellationPolicy: run.cancellationPolicy != null
          ? WorkflowCancellationPolicy.fromJson(
              _decodeMap(run.cancellationPolicy),
            )
          : null,
      cancellationData: _decodeMap(run.cancellationData),
    );
  }

  @override
  Future<T?> readStep<T>(String runId, String stepName) async {
    final ctx = _connections.context;
    final step = await ctx
        .query<StemWorkflowStep>()
        .whereEquals('runId', runId)
        .whereEquals('name', stepName)
        .whereEquals('namespace', namespace)
        .first();

    if (step == null) return null;
    return _decodeValue(step.value) as T?;
  }

  @override
  Future<void> saveStep<T>(String runId, String stepName, T value) async {
    final now = _clock.now().toUtc();

    await _connections.runInTransaction((ctx) async {
      final existing = await ctx
          .query<StemWorkflowStep>()
          .whereEquals('runId', runId)
          .whereEquals('name', stepName)
          .whereEquals('namespace', namespace)
          .first();

      if (existing != null) {
        await ctx.repository<StemWorkflowStep>().update(
          StemWorkflowStepUpdateDto(value: jsonEncode(value)),
          where: StemWorkflowStepPartial(
            runId: runId,
            name: stepName,
            namespace: namespace,
          ),
        );
      } else {
        await ctx.repository<StemWorkflowStep>().insert(
          StemWorkflowStepInsertDto(
            runId: runId,
            name: stepName,
            namespace: namespace,
            value: jsonEncode(value),
          ),
        );
      }

      // Update run's updatedAt
      final run = await ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .first();

      if (run != null) {
        await ctx.repository<StemWorkflowRun>().update(
          StemWorkflowRunUpdateDto(updatedAt: now),
          where: StemWorkflowRunPartial(id: runId, namespace: namespace),
        );
      }
    });
  }

  @override
  Future<void> suspendUntil(
    String runId,
    String stepName,
    DateTime when, {
    Map<String, Object?>? data,
  }) async {
    final now = _clock.now().toUtc();
    final metadata = _prepareSuspensionData(data, resumeAt: when);

    await _connections.runInTransaction((ctx) async {
      final run = await ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .first();

      if (run != null) {
        final updates = StemWorkflowRunUpdateDto(
          status: WorkflowStatus.suspended.name,
          resumeAt: when,
          suspensionData: jsonEncode(metadata),
          updatedAt: now,
        ).toMap();
        updates['wait_topic'] = null;
        await ctx.repository<StemWorkflowRun>().update(
          updates,
          where: StemWorkflowRunPartial(id: runId, namespace: namespace),
        );
      }
    });
  }

  @override
  Future<void> suspendOnTopic(
    String runId,
    String stepName,
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
  }) async {
    final now = _clock.now().toUtc();
    final metadata = _prepareSuspensionData(
      data,
      resumeAt: deadline,
      deadline: deadline,
      topic: topic,
    );

    await _connections.runInTransaction((ctx) async {
      final run = await ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .first();

      if (run != null) {
        final updates = StemWorkflowRunUpdateDto(
          status: WorkflowStatus.suspended.name,
          waitTopic: topic,
          resumeAt: deadline,
          suspensionData: jsonEncode(metadata),
          updatedAt: now,
        ).toMap();
        if (deadline == null) {
          updates['resume_at'] = null;
        }
        await ctx.repository<StemWorkflowRun>().update(
          updates,
          where: StemWorkflowRunPartial(id: runId, namespace: namespace),
        );
      }
    });
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
    final now = _clock.now().toUtc();

    await _connections.runInTransaction((ctx) async {
      // Check if watcher already exists
      final existing = await ctx
          .query<StemWorkflowWatcher>()
          .whereEquals('runId', runId)
          .whereEquals('namespace', namespace)
          .first();

      if (existing != null) {
        await ctx.repository<StemWorkflowWatcher>().update(
          StemWorkflowWatcherUpdateDto(
            stepName: stepName,
            topic: topic,
            data: jsonEncode(metadata),
            deadline: deadline,
            createdAt: now,
          ),
          where: StemWorkflowWatcherPartial(
            runId: runId,
            namespace: namespace,
          ),
        );
      } else {
        await ctx.repository<StemWorkflowWatcher>().insert(
          StemWorkflowWatcherInsertDto(
            runId: runId,
            stepName: stepName,
            topic: topic,
            namespace: namespace,
            data: jsonEncode(metadata),
            deadline: deadline,
            createdAt: now,
          ),
        );
      }

      // Update the associated run
      final run = await ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .first();

      if (run != null) {
        final updates = StemWorkflowRunUpdateDto(
          status: WorkflowStatus.suspended.name,
          waitTopic: topic,
          resumeAt: deadline,
          suspensionData: jsonEncode(metadata),
          updatedAt: now,
        ).toMap();
        if (deadline == null) {
          updates['resume_at'] = null;
        }
        await ctx.repository<StemWorkflowRun>().update(
          updates,
          where: StemWorkflowRunPartial(id: runId, namespace: namespace),
        );
      }
    });
  }

  @override
  Future<void> markRunning(String runId, {String? stepName}) async {
    final now = _clock.now().toUtc();

    await _connections.runInTransaction((ctx) async {
      await _deleteWatcher(ctx, runId);

      final run = await ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .first();

      if (run != null) {
        final updates = StemWorkflowRunUpdateDto(
          status: WorkflowStatus.running.name,
          updatedAt: now,
        ).toMap();
        updates['resume_at'] = null;
        updates['wait_topic'] = null;
        await ctx.repository<StemWorkflowRun>().update(
          updates,
          where: StemWorkflowRunPartial(id: runId, namespace: namespace),
        );
      }
    });
  }

  @override
  Future<void> markCompleted(String runId, Object? result) async {
    final now = _clock.now().toUtc();

    await _connections.runInTransaction((ctx) async {
      await _deleteWatcher(ctx, runId);

      final run = await ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .first();

      if (run != null) {
        final updates = StemWorkflowRunUpdateDto(
          status: WorkflowStatus.completed.name,
          result: result != null ? jsonEncode(result) : null,
          updatedAt: now,
        ).toMap();
        if (result == null) {
          updates['result'] = null;
        }
        updates['suspension_data'] = null;
        await ctx.repository<StemWorkflowRun>().update(
          updates,
          where: StemWorkflowRunPartial(id: runId, namespace: namespace),
        );
      }
    });
  }

  @override
  Future<void> markFailed(
    String runId,
    Object error,
    StackTrace stack, {
    bool terminal = false,
  }) async {
    final now = _clock.now().toUtc();

    await _connections.runInTransaction((ctx) async {
      if (terminal) {
        await _deleteWatcher(ctx, runId);
      }

      final run = await ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .first();

      if (run != null) {
        final updates = StemWorkflowRunUpdateDto(
          status: terminal ? WorkflowStatus.failed.name : null,
          lastError: jsonEncode({
            'error': error.toString(),
            'stack': stack.toString(),
          }),
          updatedAt: now,
        ).toMap();
        await ctx.repository<StemWorkflowRun>().update(
          updates,
          where: StemWorkflowRunPartial(id: runId, namespace: namespace),
        );
      }
    });
  }

  @override
  Future<void> markResumed(String runId, {Map<String, Object?>? data}) async {
    final now = _clock.now().toUtc();

    await _connections.runInTransaction((ctx) async {
      await _deleteWatcher(ctx, runId);

      final run = await ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .first();

      if (run != null) {
        final updates = StemWorkflowRunUpdateDto(
          status: WorkflowStatus.running.name,
          suspensionData: data != null ? jsonEncode(data) : null,
          updatedAt: now,
        ).toMap();
        updates['resume_at'] = null;
        updates['wait_topic'] = null;
        if (data == null) {
          updates['suspension_data'] = null;
        }
        await ctx.repository<StemWorkflowRun>().update(
          updates,
          where: StemWorkflowRunPartial(id: runId, namespace: namespace),
        );
      }
    });
  }

  @override
  Future<List<String>> dueRuns(DateTime now, {int limit = 256}) async {
    return _connections.runInTransaction((ctx) async {
      // SELECT runs where resume_at has passed
      final dueRuns = await ctx
          .query<StemWorkflowRun>()
          .whereEquals('namespace', namespace)
          .whereNotNull('resumeAt')
          .where('resumeAt', now, PredicateOperator.lessThanOrEqual)
          .whereEquals('status', WorkflowStatus.suspended.name)
          .limit(limit)
          .get();

      if (dueRuns.isEmpty) {
        return const <String>[];
      }

      // Update all to clear resume_at
      final nowUtc = now.toUtc();
      for (final run in dueRuns) {
        final updates = StemWorkflowRunUpdateDto(updatedAt: nowUtc).toMap();
        updates['resume_at'] = null;
        await ctx.repository<StemWorkflowRun>().update(
          updates,
          where: StemWorkflowRunPartial(id: run.id, namespace: namespace),
        );
      }

      return dueRuns.map((r) => r.id).toList(growable: false);
    });
  }

  @override
  Future<List<String>> runsWaitingOn(String topic, {int limit = 256}) async {
    final ctx = _connections.context;
    // Check watchers first
    final watcherRows = await ctx
        .query<StemWorkflowWatcher>()
        .whereEquals('topic', topic)
        .whereEquals('namespace', namespace)
        .limit(limit)
        .get();

    if (watcherRows.isNotEmpty) {
      return watcherRows.map((row) => row.runId).toList(growable: false);
    }

    // Fallback to runs with wait_topic
    final fallbackRows = await ctx
        .query<StemWorkflowRun>()
        .whereEquals('waitTopic', topic)
        .whereEquals('namespace', namespace)
        .limit(limit)
        .get();

    return fallbackRows.map((r) => r.id).toList(growable: false);
  }

  @override
  Future<List<WorkflowWatcherResolution>> resolveWatchers(
    String topic,
    Map<String, Object?> payload, {
    int limit = 256,
  }) async {
    return _connections.runInTransaction((ctx) async {
      final watchers = await ctx
          .query<StemWorkflowWatcher>()
          .whereEquals('topic', topic)
          .whereEquals('namespace', namespace)
          .limit(limit)
          .get();

      if (watchers.isEmpty) {
        return const <WorkflowWatcherResolution>[];
      }

      final resolutions = <WorkflowWatcherResolution>[];
      final now = _clock.now();
      final nowUtc = now.toUtc();

      for (final watcher in watchers) {
        // Build metadata for resumption
        final data = _decodeMap(watcher.data);
        final metadata = Map<String, Object?>.from(data);
        metadata['type'] = 'event';
        metadata['topic'] = topic;
        metadata['payload'] = payload;
        metadata
          ..putIfAbsent('step', () => watcher.stepName)
          ..putIfAbsent(
            'iterationStep',
            () => metadata['step'] ?? watcher.stepName,
          );
        metadata['deliveredAt'] = now.toIso8601String();

        // Update run to mark as running with resolved metadata
        final run = await ctx
            .query<StemWorkflowRun>()
            .whereEquals('id', watcher.runId)
            .whereEquals('namespace', namespace)
            .first();

        if (run != null) {
          final updates = StemWorkflowRunUpdateDto(
            status: WorkflowStatus.running.name,
            suspensionData: jsonEncode(metadata),
            updatedAt: nowUtc,
          ).toMap();
          updates['wait_topic'] = null;
          updates['resume_at'] = null;
          await ctx.repository<StemWorkflowRun>().update(
            updates,
            where: StemWorkflowRunPartial(
              id: watcher.runId,
              namespace: namespace,
            ),
          );
        }

        // Delete the watcher (resolved)
        await ctx.repository<StemWorkflowWatcher>().delete(watcher);

        resolutions.add(
          WorkflowWatcherResolution(
            runId: watcher.runId,
            stepName: watcher.stepName,
            topic: topic,
            resumeData: metadata,
          ),
        );
      }

      return resolutions;
    });
  }

  @override
  Future<List<WorkflowWatcher>> listWatchers(
    String topic, {
    int limit = 256,
  }) async {
    final ctx = _connections.context;
    final rows = await ctx
        .query<StemWorkflowWatcher>()
        .whereEquals('topic', topic)
        .whereEquals('namespace', namespace)
        .limit(limit)
        .get();

    if (rows.isEmpty) {
      return const [];
    }

    return rows
        .map(
          (row) => WorkflowWatcher(
            runId: row.runId,
            stepName: row.stepName,
            topic: topic,
            createdAt: row.createdAt,
            deadline: row.deadline,
            data: _decodeMap(row.data),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> cancel(String runId, {String? reason}) async {
    final now = _clock.now();
    final nowUtc = now.toUtc();
    final cancellation = jsonEncode({
      'reason': reason ?? 'cancelled',
      'cancelledAt': now.toIso8601String(),
    });

    await _connections.runInTransaction((ctx) async {
      await _deleteWatcher(ctx, runId);

      final run = await ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .first();

      if (run != null) {
        final updates = StemWorkflowRunUpdateDto(
          status: WorkflowStatus.cancelled.name,
          cancellationData: cancellation,
          updatedAt: nowUtc,
        ).toMap();
        updates['suspension_data'] = null;
        updates['wait_topic'] = null;
        updates['resume_at'] = null;
        await ctx.repository<StemWorkflowRun>().update(
          updates,
          where: StemWorkflowRunPartial(id: runId, namespace: namespace),
        );
      }
    });
  }

  @override
  Future<void> rewindToStep(String runId, String stepName) async {
    await _connections.runInTransaction((ctx) async {
      await _deleteWatcher(ctx, runId);

      final stepRows = await ctx
          .query<StemWorkflowStep>()
          .whereEquals('runId', runId)
          .whereEquals('namespace', namespace)
          .orderBy('name')
          .get();

      // Calculate which steps to keep
      final names = stepRows.map((row) => row.name).toList();
      final baseIndexMap = <String, int>{};
      var nextIndex = 0;
      final entryIndexes = <int>[];

      for (final name in names) {
        final base = _baseStepName(name);
        baseIndexMap.putIfAbsent(base, () => nextIndex++);
        entryIndexes.add(baseIndexMap[base]!);
      }

      final targetIndex = baseIndexMap[stepName];
      if (targetIndex == null) return;

      final keep = <StemWorkflowStepInsertDto>[];
      for (var i = 0; i < stepRows.length; i++) {
        final baseIndex = entryIndexes[i];
        if (baseIndex < targetIndex) {
          final step = stepRows[i];
          keep.add(
            StemWorkflowStepInsertDto(
              runId: runId,
              name: step.name,
              namespace: namespace,
              value: step.value,
            ),
          );
        } else {
          break;
        }
      }

      await ctx
          .query<StemWorkflowStep>()
          .whereEquals('runId', runId)
          .whereEquals('namespace', namespace)
          .delete();

      if (keep.isNotEmpty) {
        await ctx.repository<StemWorkflowStep>().insertMany(keep);
      }

      // Update run status
      final run = await ctx
          .query<StemWorkflowRun>()
          .whereEquals('id', runId)
          .whereEquals('namespace', namespace)
          .first();

      if (run != null) {
        final updates = StemWorkflowRunUpdateDto(
          status: WorkflowStatus.suspended.name,
          suspensionData: jsonEncode({
            'step': stepName,
            'iteration': 0,
            'iterationStep': stepName,
          }),
          updatedAt: _clock.now().toUtc(),
        ).toMap();
        updates['wait_topic'] = null;
        updates['resume_at'] = null;
        await ctx.repository<StemWorkflowRun>().update(
          updates,
          where: StemWorkflowRunPartial(id: runId, namespace: namespace),
        );
      }
    });
  }

  @override
  Future<List<RunState>> listRuns({
    String? workflow,
    WorkflowStatus? status,
    int limit = 50,
    int offset = 0,
  }) async {
    final ctx = _connections.context;
    var query = ctx.query<StemWorkflowRun>();
    query = query.whereEquals('namespace', namespace);

    if (workflow != null) {
      query = query.whereEquals('workflow', workflow);
    }

    if (status != null) {
      query = query.whereEquals('status', status.name);
    }

    final ids = await query
        .orderBy('updatedAt', descending: true)
        .orderBy('id', descending: true)
        .offset(offset)
        .limit(limit)
        .get()
        .then((runs) => runs.map((r) => r.id).toList());

    final results = <RunState>[];
    for (final id in ids) {
      final state = await _readRunState(ctx, id);
      if (state != null) {
        results.add(state);
      }
    }

    return results;
  }

  @override
  Future<List<WorkflowStepEntry>> listSteps(String runId) async {
    final ctx = _connections.context;
    final rows = await ctx
        .query<StemWorkflowStep>()
        .whereEquals('runId', runId)
        .whereEquals('namespace', namespace)
        .orderBy('name')
        .get();

    final entries = <WorkflowStepEntry>[];
    var position = 0;

    for (final row in rows) {
      entries.add(
        WorkflowStepEntry(
          name: row.name,
          value: _decodeValue(row.value),
          position: position,
        ),
      );
      position += 1;
    }

    return entries;
  }

  Future<void> _deleteWatcher(QueryContext ctx, String runId) async {
    final watcher = await ctx
        .query<StemWorkflowWatcher>()
        .whereEquals('runId', runId)
        .whereEquals('namespace', namespace)
        .first();

    if (watcher != null) {
      await ctx.repository<StemWorkflowWatcher>().delete(watcher);
    }
  }

  Map<String, Object?> _decodeMap(dynamic input) {
    if (input == null) return const {};
    if (input is String) {
      try {
        final decoded = jsonDecode(input);
        return decoded is Map
            ? decoded.map((key, value) => MapEntry(key as String, value))
            : const {};
      } on Object {
        return const {};
      }
    }
    if (input is Map) {
      return input.map((key, value) => MapEntry(key.toString(), value));
    }
    return const {};
  }

  Object? _decodeValue(dynamic input) {
    if (input == null) return null;
    if (input is String) {
      try {
        return jsonDecode(input);
      } on Object {
        return input;
      }
    }
    return input;
  }

  String _baseStepName(String name) {
    final index = name.indexOf('#');
    if (index == -1) return name;
    return name.substring(0, index);
  }
}
