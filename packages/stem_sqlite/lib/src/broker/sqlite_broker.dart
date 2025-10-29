import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';
import 'package:stem/stem.dart';

import '../connection.dart';
import '../database.dart';

class SqliteBroker implements Broker {
  SqliteBroker._(
    this._connections, {
    required this.defaultVisibilityTimeout,
    required this.pollInterval,
    required this.sweeperInterval,
    required this.deadLetterRetention,
  }) : _db = _connections.db {
    _startSweeper();
  }

  static Future<SqliteBroker> open(
    File file, {
    Duration defaultVisibilityTimeout = const Duration(seconds: 30),
    Duration pollInterval = const Duration(milliseconds: 250),
    Duration sweeperInterval = const Duration(seconds: 10),
    Duration deadLetterRetention = const Duration(days: 7),
  }) async {
    final connections = await SqliteConnections.open(file);
    return SqliteBroker._(
      connections,
      defaultVisibilityTimeout: defaultVisibilityTimeout,
      pollInterval: pollInterval,
      sweeperInterval: sweeperInterval,
      deadLetterRetention: deadLetterRetention,
    );
  }

  final SqliteConnections _connections;
  final StemSqliteDatabase _db;
  final Duration defaultVisibilityTimeout;
  final Duration pollInterval;
  final Duration sweeperInterval;
  final Duration deadLetterRetention;

  final Set<_Consumer> _consumers = {};
  Timer? _sweeperTimer;
  bool _closed = false;

  @override
  bool get supportsDelayed => true;

  @override
  bool get supportsPriority => true;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _sweeperTimer?.cancel();
    _sweeperTimer = null;
    for (final consumer in _consumers.toList()) {
      consumer.dispose();
      _consumers.remove(consumer);
    }
    await _connections.close();
  }

  @visibleForTesting
  Future<void> runMaintenance() => _runSweeperCycle();

  @override
  Future<void> publish(Envelope envelope, {RoutingInfo? routing}) async {
    final route =
        routing ??
        RoutingInfo.queue(queue: envelope.queue, priority: envelope.priority);
    if (route.isBroadcast) {
      throw UnsupportedError('SqliteBroker does not support broadcast routes');
    }
    final queue = (route.queue ?? envelope.queue).trim();
    if (queue.isEmpty) {
      throw ArgumentError('Resolved queue name must not be empty');
    }

    final stored = envelope.copyWith(
      queue: queue,
      priority: route.priority ?? envelope.priority,
    );

    await _connections.runInTransaction((txn) async {
      await _insertJob(
        txn,
        envelope: stored,
        queue: queue,
        priority: stored.priority,
        attempt: stored.attempt,
        notBefore: stored.notBefore?.millisecondsSinceEpoch,
      );
    });
  }

  @override
  Stream<Delivery> consume(
    RoutingSubscription subscription, {
    int prefetch = 1,
    String? consumerGroup,
    String? consumerName,
  }) {
    if (subscription.queues.isEmpty) {
      throw ArgumentError('SqliteBroker requires at least one queue');
    }
    if (subscription.queues.length > 1) {
      throw UnsupportedError(
        'SqliteBroker currently supports one queue per subscription.',
      );
    }
    final queue = subscription.queues.single;
    final id =
        consumerName ??
        'sqlite-consumer-${DateTime.now().microsecondsSinceEpoch}-${_consumers.length}';
    final controller = StreamController<Delivery>.broadcast();
    final consumer = _Consumer(
      broker: this,
      queue: queue,
      consumerId: id,
      controller: controller,
      prefetch: prefetch.clamp(1, 50),
    );
    _consumers.add(consumer);
    controller
      ..onListen = consumer.start
      ..onCancel = () {
        consumer.dispose();
        _consumers.remove(consumer);
      };
    return controller.stream;
  }

  @override
  Future<void> ack(Delivery delivery) async {
    final jobId = _parseReceipt(delivery.receipt);
    await (_db.delete(
      _db.stemQueueJobs,
    )..where((tbl) => tbl.id.equals(jobId))).go();
  }

  @override
  Future<void> nack(Delivery delivery, {bool requeue = true}) async {
    if (!requeue) {
      await deadLetter(delivery, reason: 'nack');
      return;
    }
    final jobId = _parseReceipt(delivery.receipt);
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(
      _db.stemQueueJobs,
    )..where((tbl) => tbl.id.equals(jobId))).write(
      StemQueueJobsCompanion(
        lockedAt: const Value(null),
        lockedUntil: const Value(null),
        lockedBy: const Value(null),
        attempt: Value(delivery.envelope.attempt + 1),
        notBefore: const Value(null),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<void> deadLetter(
    Delivery delivery, {
    String? reason,
    Map<String, Object?>? meta,
  }) async {
    final jobId = _parseReceipt(delivery.receipt);
    final now = DateTime.now().millisecondsSinceEpoch;
    await _connections.runInTransaction((txn) async {
      final row = await (txn.select(
        txn.stemQueueJobs,
      )..where((tbl) => tbl.id.equals(jobId))).getSingleOrNull();
      await (txn.delete(
        txn.stemQueueJobs,
      )..where((tbl) => tbl.id.equals(jobId))).go();
      if (row != null) {
        await txn
            .into(txn.stemDeadLetters)
            .insert(
              StemDeadLettersCompanion.insert(
                id: row.id,
                queue: row.queue,
                envelope: row.envelope,
                reason: Value(reason),
                meta: Value(meta == null ? null : jsonEncode(meta)),
                deadAt: now,
              ),
            );
      }
    });
  }

  @override
  Future<void> extendLease(Delivery delivery, Duration by) async {
    final jobId = _parseReceipt(delivery.receipt);
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(
      _db.stemQueueJobs,
    )..where((tbl) => tbl.id.equals(jobId))).write(
      StemQueueJobsCompanion(
        lockedUntil: Value(now + by.inMilliseconds),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<void> purge(String queue) async {
    await (_db.delete(
      _db.stemQueueJobs,
    )..where((tbl) => tbl.queue.equals(queue))).go();
  }

  @override
  Future<int?> pendingCount(String queue) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM stem_queue_jobs WHERE queue = ?1 '
          'AND (not_before IS NULL OR not_before <= ?2)',
          variables: [Variable.withString(queue), Variable.withInt(now)],
          readsFrom: {_db.stemQueueJobs},
        )
        .getSingle();
    return (result.data['c'] as num?)?.toInt();
  }

  @override
  Future<int?> inflightCount(String queue) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM stem_queue_jobs WHERE queue = ?1 '
          'AND locked_until IS NOT NULL AND locked_until > ?2',
          variables: [Variable.withString(queue), Variable.withInt(now)],
          readsFrom: {_db.stemQueueJobs},
        )
        .getSingle();
    return (result.data['c'] as num?)?.toInt();
  }

  @override
  Future<DeadLetterPage> listDeadLetters(
    String queue, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (limit <= 0) return const DeadLetterPage(entries: []);
    final entries =
        await (_db.select(_db.stemDeadLetters)
              ..where((tbl) => tbl.queue.equals(queue))
              ..orderBy([(tbl) => OrderingTerm.desc(tbl.deadAt)])
              ..limit(limit, offset: offset))
            .get()
            .then(
              (rows) => rows.map(_deadLetterFromRow).toList(growable: false),
            );
    final nextOffset = entries.length < limit ? null : offset + limit;
    return DeadLetterPage(entries: entries, nextOffset: nextOffset);
  }

  @override
  Future<DeadLetterEntry?> getDeadLetter(String queue, String id) async {
    final row =
        await (_db.select(_db.stemDeadLetters)
              ..where((tbl) => tbl.queue.equals(queue) & tbl.id.equals(id)))
            .getSingleOrNull();
    return row == null ? null : _deadLetterFromRow(row);
  }

  @override
  Future<DeadLetterReplayResult> replayDeadLetters(
    String queue, {
    int limit = 50,
    DateTime? since,
    Duration? delay,
    bool dryRun = false,
  }) async {
    final bounded = limit.clamp(1, 500);
    final sinceMs = since?.millisecondsSinceEpoch;
    final rows =
        await (_db.select(_db.stemDeadLetters)
              ..where(
                (tbl) =>
                    tbl.queue.equals(queue) &
                    (sinceMs == null
                        ? const Constant<bool>(true)
                        : tbl.deadAt.isBiggerOrEqualValue(sinceMs)),
              )
              ..orderBy([(tbl) => OrderingTerm.desc(tbl.deadAt)])
              ..limit(bounded))
            .get();

    final entries = rows.map(_deadLetterFromRow).toList(growable: false);
    if (dryRun || entries.isEmpty) {
      return DeadLetterReplayResult(entries: entries, dryRun: true);
    }

    await _connections.runInTransaction((txn) async {
      for (final entry in entries) {
        final updatedEnvelope = delay == null
            ? entry.envelope
            : entry.envelope.copyWith(notBefore: DateTime.now().add(delay));
        await _insertJob(
          txn,
          envelope: updatedEnvelope,
          queue: queue,
          priority: updatedEnvelope.priority,
          attempt: updatedEnvelope.attempt,
          notBefore: updatedEnvelope.notBefore?.millisecondsSinceEpoch,
        );
        await (txn.delete(
          txn.stemDeadLetters,
        )..where((tbl) => tbl.id.equals(entry.envelope.id))).go();
      }
    });

    return DeadLetterReplayResult(entries: entries, dryRun: false);
  }

  @override
  Future<int> purgeDeadLetters(
    String queue, {
    DateTime? since,
    int? limit,
  }) async {
    final sinceMs = since?.millisecondsSinceEpoch;
    if (limit != null) {
      final ids =
          await (_db.select(_db.stemDeadLetters)
                ..where((tbl) => tbl.queue.equals(queue))
                ..orderBy([(tbl) => OrderingTerm.desc(tbl.deadAt)])
                ..limit(limit))
              .map((row) => row.id)
              .get();
      if (ids.isEmpty) return 0;
      await (_db.delete(
        _db.stemDeadLetters,
      )..where((tbl) => tbl.id.isIn(ids))).go();
      return ids.length;
    }

    final delete = _db.delete(_db.stemDeadLetters)
      ..where((tbl) => tbl.queue.equals(queue));
    if (sinceMs != null) {
      delete.where((tbl) => tbl.deadAt.isBiggerOrEqualValue(sinceMs));
    }
    return delete.go();
  }

  Future<_QueuedJob?> _claimNextJob(String queue, String consumerId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final visibilityMs = defaultVisibilityTimeout.inMilliseconds;

    return _connections.runInTransaction((txn) async {
      final candidate = await txn
          .customSelect(
            'SELECT * FROM stem_queue_jobs WHERE queue = ?1 '
            'AND (not_before IS NULL OR not_before <= ?2) '
            'AND (locked_until IS NULL OR locked_until <= ?2) '
            'ORDER BY priority DESC, created_at ASC LIMIT 1',
            variables: [Variable.withString(queue), Variable.withInt(now)],
            readsFrom: {txn.stemQueueJobs},
          )
          .getSingleOrNull();
      if (candidate == null) return null;

      final id = candidate.data['id'] as String;
      final updated = await txn.customUpdate(
        'UPDATE stem_queue_jobs SET locked_at = ?2, locked_until = ?3, '
        'locked_by = ?4, updated_at = ?5 '
        'WHERE id = ?1 AND (locked_until IS NULL OR locked_until <= ?6) '
        'AND (not_before IS NULL OR not_before <= ?6)',
        variables: [
          Variable.withString(id),
          Variable.withInt(now),
          Variable.withInt(now + visibilityMs),
          Variable.withString(consumerId),
          Variable.withInt(now),
          Variable.withInt(now),
        ],
        updates: {txn.stemQueueJobs},
      );
      if (updated == 0) return null;
      return _QueuedJob.fromRow(candidate.data);
    });
  }

  void _startSweeper() {
    _sweeperTimer?.cancel();
    _sweeperTimer = Timer.periodic(sweeperInterval, (_) {
      if (_closed) return;
      unawaited(_runSweeperCycle());
    });
  }

  Future<void> _runSweeperCycle() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _connections.runInTransaction((txn) async {
      await txn.customUpdate(
        'UPDATE stem_queue_jobs SET locked_at = NULL, locked_until = NULL, '
        'locked_by = NULL WHERE locked_until IS NOT NULL AND locked_until <= ?1',
        variables: [Variable.withInt(now)],
        updates: {txn.stemQueueJobs},
      );
      if (!deadLetterRetention.isNegative &&
          deadLetterRetention > Duration.zero) {
        final cutoff = now - deadLetterRetention.inMilliseconds;
        await txn.customUpdate(
          'DELETE FROM stem_dead_letters WHERE dead_at <= ?1',
          variables: [Variable.withInt(cutoff)],
          updates: {txn.stemDeadLetters},
        );
      }
    });
  }

  String _parseReceipt(String receipt) => receipt;

  Future<void> _insertJob(
    StemSqliteDatabase db, {
    required Envelope envelope,
    required String queue,
    required int priority,
    required int attempt,
    int? notBefore,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final job = StemQueueJobsCompanion(
      id: Value(envelope.id),
      queue: Value(queue),
      envelope: Value(jsonEncode(envelope.toJson())),
      attempt: Value(attempt),
      maxRetries: Value(envelope.maxRetries),
      priority: Value(priority),
      notBefore: Value(notBefore),
      lockedAt: const Value(null),
      lockedUntil: const Value(null),
      lockedBy: const Value(null),
      createdAt: Value(now),
      updatedAt: Value(now),
    );
    await db.into(db.stemQueueJobs).insertOnConflictUpdate(job);
  }

  DeadLetterEntry _deadLetterFromRow(StemDeadLetter row) {
    final envelope = Envelope.fromJson(
      (jsonDecode(row.envelope) as Map).cast<String, Object?>(),
    );
    return DeadLetterEntry(
      envelope: envelope,
      reason: row.reason,
      meta: row.meta == null
          ? null
          : (jsonDecode(row.meta!) as Map).cast<String, Object?>(),
      deadAt: DateTime.fromMillisecondsSinceEpoch(row.deadAt),
    );
  }
}

class _Consumer {
  _Consumer({
    required this.broker,
    required this.queue,
    required this.consumerId,
    required this.controller,
    required this.prefetch,
  });

  final SqliteBroker broker;
  final String queue;
  final String consumerId;
  final StreamController<Delivery> controller;
  final int prefetch;

  bool _running = false;
  bool _loopActive = false;

  void start() {
    if (_running) return;
    _running = true;
    if (!_loopActive) {
      _loopActive = true;
      unawaited(_loop());
    }
  }

  void dispose() {
    _running = false;
    if (!controller.isClosed) {
      unawaited(controller.close());
    }
  }

  Future<void> _loop() async {
    while (_running && !controller.isClosed && !broker._closed) {
      try {
        final jobs = <_QueuedJob>[];
        for (var i = 0; i < prefetch; i++) {
          final job = await broker._claimNextJob(queue, consumerId);
          if (job == null) break;
          jobs.add(job);
        }
        if (jobs.isEmpty) {
          await Future<void>.delayed(broker.pollInterval);
          continue;
        }
        final leaseExpiresAt = DateTime.now().add(
          broker.defaultVisibilityTimeout,
        );
        for (final job in jobs) {
          if (!_running || controller.isClosed) break;
          controller.add(job.toDelivery(leaseExpiresAt: leaseExpiresAt));
        }
      } catch (_) {
        if (!_running || controller.isClosed) break;
        await Future<void>.delayed(broker.pollInterval);
      }
    }
    _loopActive = false;
  }
}

class _QueuedJob {
  _QueuedJob({required this.id, required this.queue, required this.envelope});

  final String id;
  final String queue;
  final Envelope envelope;

  factory _QueuedJob.fromRow(Map<String, Object?> row) {
    final envelopeMap = (jsonDecode(row['envelope'] as String) as Map)
        .cast<String, Object?>();
    return _QueuedJob(
      id: row['id'] as String,
      queue: row['queue'] as String,
      envelope: Envelope.fromJson(envelopeMap),
    );
  }

  Delivery toDelivery({required DateTime leaseExpiresAt}) {
    return Delivery(
      envelope: envelope,
      receipt: id,
      leaseExpiresAt: leaseExpiresAt,
      route: RoutingInfo.queue(queue: queue, priority: envelope.priority),
    );
  }
}
