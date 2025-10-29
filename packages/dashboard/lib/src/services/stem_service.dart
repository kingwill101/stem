// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:stem/stem.dart';
import 'package:stem_cli/stem_cli.dart';
import 'package:stem_redis/stem_redis.dart';
import 'package:stem_sqlite/stem_sqlite.dart';

import '../config/config.dart';
import 'models.dart';

abstract class DashboardDataSource {
  Future<List<QueueSummary>> fetchQueueSummaries();
  Future<List<WorkerStatus>> fetchWorkerStatuses();
  Future<void> enqueueTask(EnqueueRequest request);
  Future<DeadLetterReplayResult> replayDeadLetters(
    String queue, {
    int limit = 50,
    bool dryRun = false,
  });
  Future<List<ControlReplyMessage>> sendControlCommand(
    ControlCommandMessage command, {
    Duration timeout,
  });
  Future<void> close();
}

class StemDashboardService implements DashboardDataSource {
  StemDashboardService._({required DashboardConfig config})
    : _config = config,
      _namespace = config.namespace,
      _environment = Map<String, String>.from(config.environment);

  final DashboardConfig _config;
  final String _namespace;
  final Map<String, String> _environment;

  static Future<StemDashboardService> connect(DashboardConfig config) async =>
      StemDashboardService._(config: config);

  @override
  Future<List<QueueSummary>> fetchQueueSummaries() => _withContext((ctx) async {
    final broker = ctx.broker;
    final queues = await _discoverQueues(ctx);
    final summaries = <QueueSummary>[];
    for (final queue in queues) {
      final pending = await broker.pendingCount(queue) ?? 0;
      final inflight = await broker.inflightCount(queue) ?? 0;
      final dead = await _deadLetterCount(broker, queue);
      summaries.add(
        QueueSummary(
          queue: queue,
          pending: pending,
          inflight: inflight,
          deadLetters: dead,
        ),
      );
    }
    summaries.sort((a, b) => a.queue.compareTo(b.queue));
    return summaries;
  });

  @override
  Future<List<WorkerStatus>> fetchWorkerStatuses() => _withContext((ctx) async {
    final backend = ctx.backend;
    if (backend == null) return const [];
    try {
      final heartbeats = await backend.listWorkerHeartbeats();
      final statuses =
          heartbeats.map(WorkerStatus.fromHeartbeat).toList(growable: false)
            ..sort((a, b) => a.workerId.compareTo(b.workerId));
      return statuses;
    } catch (_) {
      return const [];
    }
  });

  @override
  Future<void> enqueueTask(EnqueueRequest request) => _withContext((ctx) async {
    final envelope = Envelope(
      id: generateEnvelopeId(),
      name: request.task,
      args: request.args,
      queue: request.queue,
      priority: request.priority,
      maxRetries: request.maxRetries,
      meta: const {'source': 'dashboard'},
    );
    await ctx.broker.publish(envelope);
  });

  @override
  Future<DeadLetterReplayResult> replayDeadLetters(
    String queue, {
    int limit = 50,
    bool dryRun = false,
  }) => _withContext((ctx) async {
    final bounded = limit.clamp(1, 500).toInt();
    return ctx.broker.replayDeadLetters(queue, limit: bounded, dryRun: dryRun);
  });

  @override
  Future<List<ControlReplyMessage>> sendControlCommand(
    ControlCommandMessage command, {
    Duration timeout = const Duration(seconds: 5),
  }) => _withContext((ctx) async {
    final broker = ctx.broker;
    final replyQueue = ControlQueueNames.reply(_namespace, command.requestId);
    await _purgeQueue(broker, replyQueue);

    final targets = command.targets.isEmpty
        ? <String>[ControlQueueNames.broadcast(_namespace)]
        : command.targets
              .map((target) => ControlQueueNames.worker(_namespace, target))
              .toList();

    final now = DateTime.now().toUtc();
    for (final queue in targets) {
      final envelope = Envelope(
        id: generateEnvelopeId(),
        name: ControlEnvelopeTypes.command,
        queue: queue,
        args: command.toMap(),
        headers: {
          'stem-control': '1',
          'stem-reply-to': replyQueue,
          'stem-command-source': 'dashboard',
        },
        meta: const {'source': 'dashboard'},
        enqueuedAt: now,
      );
      await broker.publish(envelope);
    }

    final expectedReplies = command.targets.isEmpty
        ? null
        : command.targets.length;
    final prefetch = expectedReplies == null ? 8 : expectedReplies.clamp(1, 32);

    final subscription = broker.consume(
      RoutingSubscription.singleQueue(replyQueue),
      consumerGroup: _controlConsumerGroup,
      consumerName: 'dashboard-${command.requestId}',
      prefetch: prefetch,
    );

    final iterator = StreamIterator(subscription);
    final replies = <ControlReplyMessage>[];
    final deadline = DateTime.now().add(timeout);

    try {
      while (DateTime.now().isBefore(deadline)) {
        final remaining = deadline.difference(DateTime.now());
        bool hasNext;
        try {
          hasNext = await iterator.moveNext().timeout(remaining);
        } on TimeoutException {
          break;
        }
        if (!hasNext) break;

        final delivery = iterator.current;
        try {
          final reply = controlReplyFromEnvelope(delivery.envelope);
          replies.add(reply);
          await broker.ack(delivery);
        } catch (_) {
          await broker.nack(delivery, requeue: false);
        }

        if (expectedReplies != null && replies.length >= expectedReplies) {
          break;
        }
      }
    } finally {
      await iterator.cancel();
      await _purgeQueue(broker, replyQueue);
    }

    return replies;
  });

  @override
  Future<void> close() async {
    // No persistent connections to close; contexts are per-call.
  }

  Future<T> _withContext<T>(Future<T> Function(CliContext ctx) action) async {
    final ctx = await createDefaultContext(environment: _environment);
    try {
      // Ensure primary queue has a consumer group before we read metrics.
      await _ensureGroupExists(ctx);
      return await action(ctx);
    } finally {
      await ctx.dispose();
    }
  }

  Future<Set<String>> _discoverQueues(CliContext ctx) async {
    final names = <String>{_config.stem.defaultQueue};
    names.addAll(_config.stem.workerQueues);
    names.addAll(_config.routing.config.queues.keys);

    final backend = ctx.backend;
    if (backend != null) {
      try {
        final heartbeats = await backend.listWorkerHeartbeats();
        for (final heartbeat in heartbeats) {
          for (final queue in heartbeat.queues) {
            names.add(queue.name);
          }
        }
      } catch (_) {
        // Ignore discovery errors from backend.
      }
    }

    names.removeWhere((value) => value.trim().isEmpty);
    if (names.isEmpty) {
      names.add(_config.stem.defaultQueue);
    }
    return names;
  }

  Future<int> _deadLetterCount(Broker broker, String queue) async {
    var total = 0;
    var offset = 0;
    const pageSize = 200;
    const maxIterations = 50;

    for (var iteration = 0; iteration < maxIterations; iteration++) {
      final page = await broker.listDeadLetters(
        queue,
        limit: pageSize,
        offset: offset,
      );
      total += page.entries.length;
      final next = page.nextOffset;
      if (next == null) break;
      offset = next;
    }
    return total;
  }

  Future<void> _ensureGroupExists(CliContext ctx) async {
    final broker = ctx.broker;
    if (broker is RedisStreamsBroker) {
      // Touch the default queue to force group creation if it doesn't exist.
      await broker.pendingCount(_config.stem.defaultQueue);
    }
  }

  Future<void> _purgeQueue(Broker broker, String queue) async {
    try {
      await broker.purge(queue);
    } catch (_) {
      // Some brokers may not support purge; ignore failures.
    }
  }

  static const _controlConsumerGroup = 'stem-dashboard-control';
}

class SqliteDashboardService implements DashboardDataSource {
  SqliteDashboardService._({
    required this.databaseFile,
    required SqliteConnections metrics,
    required SqliteBroker broker,
  }) : _metrics = metrics,
       _broker = broker;

  static Future<SqliteDashboardService> connect(File file) async {
    file.parent.createSync(recursive: true);
    final metrics = await SqliteConnections.open(file, readOnly: true);
    final broker = await SqliteBroker.open(file);
    return SqliteDashboardService._(
      databaseFile: file,
      metrics: metrics,
      broker: broker,
    );
  }

  final File databaseFile;
  final SqliteConnections _metrics;
  final SqliteBroker _broker;

  StemSqliteDatabase get _db => _metrics.db;

  @override
  Future<List<QueueSummary>> fetchQueueSummaries() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final queueRows = await _db
        .customSelect(
          'SELECT queue FROM stem_queue_jobs '
          'UNION '
          'SELECT queue FROM stem_dead_letters',
          readsFrom: {_db.stemQueueJobs, _db.stemDeadLetters},
        )
        .get();

    final queues = queueRows
        .map((row) => (row.data['queue'] as String?)?.trim())
        .whereType<String>()
        .where((queue) => queue.isNotEmpty)
        .toSet();
    if (queues.isEmpty) {
      queues.add('default');
    }

    final pendingRows = await _db
        .customSelect(
          'SELECT queue, COUNT(*) AS c FROM stem_queue_jobs '
          'WHERE (not_before IS NULL OR not_before <= ?1) '
          'AND (locked_until IS NULL OR locked_until <= ?1) '
          'GROUP BY queue',
          variables: [Variable.withInt(now)],
          readsFrom: {_db.stemQueueJobs},
        )
        .get();
    final inflightRows = await _db
        .customSelect(
          'SELECT queue, COUNT(*) AS c FROM stem_queue_jobs '
          'WHERE locked_until IS NOT NULL AND locked_until > ?1 '
          'GROUP BY queue',
          variables: [Variable.withInt(now)],
          readsFrom: {_db.stemQueueJobs},
        )
        .get();
    final deadRows = await _db
        .customSelect(
          'SELECT queue, COUNT(*) AS c FROM stem_dead_letters GROUP BY queue',
          readsFrom: {_db.stemDeadLetters},
        )
        .get();

    Map<String, int> buildCountMap(List<Map<String, Object?>> rows) {
      final counts = <String, int>{};
      for (final raw in rows) {
        final queue = raw['queue'] as String?;
        final count = raw['c'] as num?;
        if (queue != null && count != null) {
          counts[queue] = count.toInt();
        }
      }
      return counts;
    }

    final pendingMap = buildCountMap(
      pendingRows.map((row) => row.data).toList(growable: false),
    );
    final inflightMap = buildCountMap(
      inflightRows.map((row) => row.data).toList(growable: false),
    );
    final deadMap = buildCountMap(
      deadRows.map((row) => row.data).toList(growable: false),
    );

    final orderedQueues = queues.toList()..sort();
    return orderedQueues
        .map(
          (queue) => QueueSummary(
            queue: queue,
            pending: pendingMap[queue] ?? 0,
            inflight: inflightMap[queue] ?? 0,
            deadLetters: deadMap[queue] ?? 0,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<WorkerStatus>> fetchWorkerStatuses() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await _db
        .customSelect(
          'SELECT worker_id, namespace, timestamp, isolate_count, inflight, '
          'queues, last_lease_renewal, version, extras '
          'FROM stem_worker_heartbeats '
          'WHERE expires_at > ?1 '
          'ORDER BY worker_id ASC',
          variables: [Variable.withInt(now)],
          readsFrom: {_db.stemWorkerHeartbeats},
        )
        .get();
    if (rows.isEmpty) return const [];

    return rows.map((row) => _statusFromRow(row.data)).toList(growable: false);
  }

  @override
  Future<void> enqueueTask(EnqueueRequest request) async {
    final envelope = Envelope(
      id: generateEnvelopeId(),
      name: request.task,
      args: request.args,
      queue: request.queue,
      priority: request.priority,
      maxRetries: request.maxRetries,
      meta: const {'source': 'dashboard'},
    );
    await _broker.publish(envelope);
  }

  @override
  Future<DeadLetterReplayResult> replayDeadLetters(
    String queue, {
    int limit = 50,
    bool dryRun = false,
  }) {
    final bounded = limit.clamp(1, 500);
    return _broker.replayDeadLetters(queue, limit: bounded, dryRun: dryRun);
  }

  @override
  Future<List<ControlReplyMessage>> sendControlCommand(
    ControlCommandMessage command, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    // Control channels are not yet supported for SQLite deployments.
    return const [];
  }

  @override
  Future<void> close() async {
    await _broker.close();
    await _metrics.close();
  }

  WorkerStatus _statusFromRow(Map<String, Object?> row) {
    final timestamp = (row['timestamp'] as num?)?.toInt() ?? 0;
    return WorkerStatus(
      workerId: row['worker_id'] as String? ?? 'unknown',
      namespace: row['namespace'] as String? ?? 'stem',
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp).toUtc(),
      isolateCount: (row['isolate_count'] as num?)?.toInt() ?? 0,
      inflight: (row['inflight'] as num?)?.toInt() ?? 0,
      queues: _decodeQueues(row['queues'] as String? ?? '[]'),
      extras: _decodeExtras(row['extras'] as String?),
    );
  }

  Map<String, Object?> _decodeExtras(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      return (jsonDecode(raw) as Map).cast<String, Object?>();
    } catch (_) {
      return const {};
    }
  }

  List<WorkerQueueInfo> _decodeQueues(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map(
              (entry) =>
                  WorkerQueueInfo.fromJson(entry.cast<String, Object?>()),
            )
            .toList(growable: false);
      }
    } catch (_) {
      // ignore
    }
    return const [];
  }
}
