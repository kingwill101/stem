import 'dart:convert';

import 'package:ormed/ormed.dart';
import 'package:stem/stem.dart';

import 'package:stem_postgres/src/connection.dart';
import 'package:stem_postgres/src/database/models/workflow_models.dart';

/// PostgreSQL-backed implementation of [ScheduleStore] using ormed ORM.
class PostgresScheduleStore implements ScheduleStore {
  /// Creates a schedule store backed by PostgreSQL.
  PostgresScheduleStore._(this._connections, {required this.namespace});

  final PostgresConnections _connections;
  final String namespace;

  /// Connects to a PostgreSQL database and ensures schedule tables exist.
  static Future<PostgresScheduleStore> connect(
    String uri, {
    String namespace = 'stem',
    String schema = 'public',
    String? applicationName,
    TlsConfig? tls,
  }) async {
    final resolvedNamespace =
        namespace.trim().isEmpty ? 'stem' : namespace.trim();
    final connections = await PostgresConnections.open(connectionString: uri);
    return PostgresScheduleStore._(
      connections,
      namespace: resolvedNamespace,
    );
  }

  /// Creates a schedule store using an existing [DataSource].
  ///
  /// The caller remains responsible for disposing the [DataSource].
  static PostgresScheduleStore fromDataSource(
    DataSource dataSource, {
    String namespace = 'stem',
  }) {
    final resolvedNamespace =
        namespace.trim().isNotEmpty ? namespace.trim() : 'stem';
    final connections = PostgresConnections.fromDataSource(dataSource);
    return PostgresScheduleStore._(
      connections,
      namespace: resolvedNamespace,
    );
  }

  /// Closes the schedule store and releases database resources.
  Future<void> close() async {
    await _connections.close();
  }

  @override
  Future<List<ScheduleEntry>> due(DateTime now, {int limit = 100}) async {
    final ctx = _connections.context;
    // Acquire due entries and push their next_run_at slightly into the future
    // to avoid immediate reacquisition.
    final dueEntries = await ctx
        .query<$StemScheduleEntry>()
        .whereEquals('namespace', namespace)
        .where((PredicateBuilder<$StemScheduleEntry> q) {
          q
            ..where('enabled', true, PredicateOperator.equals)
            ..where('nextRunAt', now, PredicateOperator.lessThanOrEqual);
        })
        .orderBy('nextRunAt')
        .limit(limit)
        .get();

    if (dueEntries.isEmpty) return const [];

    const bump = Duration(milliseconds: 300);
    final nextWindow = now.add(bump);

    // Minimal lock semantics: advance next_run_at slightly.
    await _connections.runInTransaction((tx) async {
      for (final entry in dueEntries) {
        await tx.repository<$StemScheduleEntry>().update(
          $StemScheduleEntry(
            id: entry.id,
            namespace: entry.namespace,
            taskName: entry.taskName,
            queue: entry.queue,
            spec: entry.spec,
            args: entry.args,
            kwargs: entry.kwargs,
            enabled: entry.enabled,
            jitter: entry.jitter,
            lastRunAt: entry.lastRunAt,
            nextRunAt: nextWindow,
            lastJitter: entry.lastJitter,
            lastError: entry.lastError,
            timezone: entry.timezone,
            totalRunCount: entry.totalRunCount,
            lastSuccessAt: entry.lastSuccessAt,
            lastErrorAt: entry.lastErrorAt,
            drift: entry.drift,
            expireAt: entry.expireAt,
            meta: entry.meta,
            createdAt: entry.createdAt,
            updatedAt: now,
            version: entry.version,
          ),
        );
      }
    });

    return dueEntries.map(_toDomain).toList();
  }

  @override
  Future<void> upsert(ScheduleEntry entry) async {
    final now = DateTime.now().toUtc();
    final ctx = _connections.context;

    final existing = await ctx
        .query<$StemScheduleEntry>()
        .whereEquals('id', entry.id)
        .whereEquals('namespace', namespace)
        .first();

    final model = $StemScheduleEntry(
      id: entry.id,
      namespace: namespace,
      taskName: entry.taskName,
      queue: entry.queue,
      spec: entry.spec.toString(),
      args: entry.args.isNotEmpty ? jsonEncode(entry.args) : null,
      kwargs: entry.kwargs.isNotEmpty ? jsonEncode(entry.kwargs) : null,
      enabled: entry.enabled,
      jitter: entry.jitter?.inMilliseconds,
      lastRunAt: entry.lastRunAt,
      nextRunAt: entry.nextRunAt,
      lastJitter: entry.lastJitter?.inMilliseconds,
      lastError: entry.lastError,
      timezone: entry.timezone,
      totalRunCount: entry.totalRunCount,
      lastSuccessAt: entry.lastSuccessAt,
      lastErrorAt: entry.lastErrorAt,
      drift: entry.drift?.inMilliseconds,
      expireAt: entry.expireAt,
      meta: entry.meta.isNotEmpty ? jsonEncode(entry.meta) : null,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      version: existing?.version ?? 0,
    );

    if (existing != null) {
      await ctx.repository<$StemScheduleEntry>().update(model);
    } else {
      await ctx.repository<$StemScheduleEntry>().insert(model);
    }
  }

  @override
  Future<void> remove(String id) async {
    final ctx = _connections.context;
    final entry = await ctx
        .query<$StemScheduleEntry>()
        .whereEquals('id', id)
        .whereEquals('namespace', namespace)
        .first();

    if (entry != null) {
      await ctx.repository<$StemScheduleEntry>().delete(entry);
    }
  }

  @override
  Future<List<ScheduleEntry>> list({int? limit}) async {
    final ctx = _connections.context;
    var query = ctx.query<$StemScheduleEntry>();
    query = query.whereEquals('namespace', namespace);

    if (limit != null) {
      query = query.limit(limit);
    }

    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  @override
  Future<ScheduleEntry?> get(String id) async {
    final ctx = _connections.context;
    final entry = await ctx
        .query<$StemScheduleEntry>()
        .whereEquals('id', id)
        .whereEquals('namespace', namespace)
        .first();

    return entry == null ? null : _toDomain(entry);
  }

  @override
  Future<void> markExecuted(
    String id, {
    required DateTime scheduledFor,
    required DateTime executedAt,
    Duration? jitter,
    String? lastError,
    bool success = true,
    Duration? runDuration,
    DateTime? nextRunAt,
    Duration? drift,
  }) async {
    return _connections.runInTransaction((ctx) async {
      final entry = await ctx
          .query<$StemScheduleEntry>()
          .whereEquals('id', id)
          .whereEquals('namespace', namespace)
          .first();

      if (entry != null) {
        await ctx.repository<$StemScheduleEntry>().update(
          $StemScheduleEntry(
            id: entry.id,
            namespace: entry.namespace,
            taskName: entry.taskName,
            queue: entry.queue,
            spec: entry.spec,
            args: entry.args,
            kwargs: entry.kwargs,
            enabled: entry.enabled,
            jitter: entry.jitter,
            lastRunAt: executedAt,
            nextRunAt: nextRunAt,
            lastJitter: jitter?.inMilliseconds,
            lastError: lastError,
            timezone: entry.timezone,
            totalRunCount: entry.totalRunCount + 1,
            lastSuccessAt: success ? executedAt : null,
            lastErrorAt: !success ? executedAt : null,
            drift: drift?.inMilliseconds,
            expireAt: entry.expireAt,
            meta: entry.meta,
            createdAt: entry.createdAt,
            updatedAt: DateTime.now().toUtc(),
            version: entry.version,
          ),
        );
      }
    });
  }

  ScheduleEntry _toDomain(StemScheduleEntry model) {
    ScheduleSpec spec;
    try {
      // Try parsing cron from spec string
      spec = _parseScheduleSpec(model.spec);
    } on Object {
      // Fallback to default cron spec
      spec = CronScheduleSpec(expression: '0 0 * * *');
    }
    return ScheduleEntry(
      id: model.id,
      taskName: model.taskName,
      queue: model.queue,
      spec: spec,
      args: _decodeMap(model.args),
      kwargs: _decodeMap(model.kwargs),
      enabled: model.enabled,
      jitter: model.jitter != null
          ? Duration(milliseconds: model.jitter!)
          : null,
      lastRunAt: model.lastRunAt,
      nextRunAt: model.nextRunAt,
      lastJitter: model.lastJitter != null
          ? Duration(milliseconds: model.lastJitter!)
          : null,
      lastError: model.lastError,
      timezone: model.timezone,
      totalRunCount: model.totalRunCount,
      lastSuccessAt: model.lastSuccessAt,
      lastErrorAt: model.lastErrorAt,
      drift: model.drift != null ? Duration(milliseconds: model.drift!) : null,
      expireAt: model.expireAt,
      createdAt: model.createdAt,
      updatedAt: model.updatedAt,
      meta: _decodeMap(model.meta),
      version: model.version ?? 0,
    );
  }

  ScheduleSpec _parseScheduleSpec(String spec) {
    // Very simple parser - assumes cron format
    // In reality, this should match your ScheduleSpec serialization format
    return CronScheduleSpec(expression: spec);
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
}
