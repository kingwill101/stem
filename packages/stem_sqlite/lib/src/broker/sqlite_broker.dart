import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:stem/stem.dart';

import '../database.dart';
import '../connection.dart';

class SqliteBroker implements Broker {
  SqliteBroker._(
    this._connections, {
    required this.defaultVisibilityTimeout,
    required this.pollInterval,
  }) : _db = _connections.database {
    _startSweeper();
  }

  static Future<SqliteBroker> open(
    File file, {
    Duration defaultVisibilityTimeout = const Duration(seconds: 30),
    Duration pollInterval = const Duration(milliseconds: 250),
  }) async {
    final connections = await SqliteConnections.open(file);
    return SqliteBroker._(
      connections,
      defaultVisibilityTimeout: defaultVisibilityTimeout,
      pollInterval: pollInterval,
    );
  }

  final SqliteConnections _connections;
  final StemSqliteDatabase _db;
  final Duration defaultVisibilityTimeout;
  final Duration pollInterval;

  final Set<_Consumer> _consumers = {};
  Timer? _sweeper;
  bool _closed = false;

  @override
  bool get supportsDelayed => true;

  @override
  bool get supportsPriority => true;

  @override
  Future<void> publish(Envelope envelope, {RoutingInfo? routing}) async {
    final route = routing ??
        RoutingInfo.queue(queue: envelope.queue, priority: envelope.priority);
    if (route.isBroadcast) {
      throw UnsupportedError('SqliteBroker does not support broadcast routes');
    }
    await _insertJob(
      envelope: envelope,
      queue: route.queue ?? envelope.queue,
      priority: route.priority ?? envelope.priority,
      attempt: envelope.attempt,
      notBefore: envelope.notBefore?.millisecondsSinceEpoch,
    );
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
        'SqliteBroker only supports one queue per subscription.',
      );
    }
    final queue = subscription.queues.single;
    final id = consumerName ??
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
    consumer.start();
    controller.onCancel = () {
      consumer.dispose();
      _consumers.remove(consumer);
    };
    return controller.stream;
  }

  @override
  Future<void> ack(Delivery delivery) async {
    final jobId = _parseReceipt(delivery.receipt);
    await (_db.delete(_db.stemQueueJobs)
          ..where((tbl) => tbl.id.equals(jobId)))
        .go();
  }

  @override
  Future<void> nack(Delivery delivery, {bool requeue = true}) async {
    final jobId = _parseReceipt(delivery.receipt);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!requeue) {
      await _db.transaction(() async {
        final row = await (_db.select(_db.stemQueueJobs)
              ..where((tbl) => tbl.id.equals(jobId)))
            .getSingleOrNull();
        await (_db.delete(_db.stemQueueJobs)
              ..where((tbl) => tbl.id.equals(jobId)))
            .go();
        if (row != null) {
          await _db.into(_db.stemDeadLetters).insert(
                StemDeadLettersCompanion.insert(
                  id: row.id,
                  queue: row.queue,
                  envelope: row.envelope,
                  reason: const Value('nack'),
                  meta: const Value(null),
                  deadAt: Value(now),
                ),
              );
        }
      });
      return;
    }

    await (_db.update(_db.stemQueueJobs)
          ..where((tbl) => tbl.id.equals(jobId)))
        .write(
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
    await _db.transaction(() async {
      final row = await (_db.select(_db.stemQueueJobs)
            ..where((tbl) => tbl.id.equals(jobId)))
          .getSingleOrNull();
      await (_db.delete(_db.stemQueueJobs)
            ..where((tbl) => tbl.id.equals(jobId)))
          .go();
      if (row != null) {
        await _db.into(_db.stemDeadLetters).insert(
              StemDeadLettersCompanion.insert(
                id: row.id,
                queue: row.queue,
                envelope: row.envelope,
                reason: Value(reason),
                meta: Value(meta == null ? null : jsonEncode(meta)),
                deadAt: Value(now),
              ),
            );
      }
    });
  }

  @override
  Future<void> extendLease(Delivery delivery, Duration by) async {
    final jobId = _parseReceipt(delivery.receipt);
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.stemQueueJobs)
          ..where((tbl) => tbl.id.equals(jobId)))
        .write(
      StemQueueJobsCompanion(
        lockedUntil: Value(now + by.inMilliseconds),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<void> purge(String queue) async {
    await (_db.delete(_db.stemQueueJobs)
          ..where((tbl) => tbl.queue.equals(queue)))
        .go();
  }

  @override
  Future<int?> pendingCount(String queue) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = await _db.customSelect(
      'SELECT COUNT(*) AS c FROM stem_queue_jobs '
      'WHERE queue = ?1 AND (not_before IS NULL OR not_before <= ?2)',
      variables: [Variable.withString(queue), Variable.withInt(now)],
      readsFrom: {_db.stemQueueJobs},
    ).getSingle();
    return result.data['c'] as int;
  }

  @override
  Future<int?> inflightCount(String queue) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = await _db.customSelect(
      'SELECT COUNT(*) AS c FROM stem_queue_jobs '
      'WHERE queue = ?1 AND locked_until IS NOT NULL AND locked_until > ?2',
      variables: [Variable.withString(queue), Variable.withInt(now)],
      readsFrom: {_db.stemQueueJobs},
    ).getSingle();
    return result.data['c'] as int;
  }

  @override
  Future<DeadLetterPage> listDeadLetters(
    String queue, {
    int limit = 50,
    int offset = 0,
  }) async {
    final query = (_db.select(_db.stemDeadLetters)
          ..where((tbl) => tbl.queue.equals(queue))
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.deadAt)])
          ..limit(limit, offset: offset));
    final rows = await query.get();
    final entries = rows
        .map(
          (row) => DeadLetterEntry(
            envelope: Envelope.fromJson(
              (jsonDecode(row.envelope) as Map).cast<String, Object?>(),
            ),
            reason: row.reason,
            meta: row.meta == null
                ? null
                : (jsonDecode(row.meta!) as Map).cast<String, Object?>(),
            deadAt: DateTime.fromMillisecondsSinceEpoch(row.deadAt),
          ),
        )
        .toList();
    final nextOffset = entries.length < limit ? null : offset + limit;
    return DeadLetterPage(entries: entries, nextOffset: nextOffset);
  }

  @override
  Future<DeadLetterEntry?> getDeadLetter(String queue, String id) async {
    final row = await (_db.select(_db.stemDeadLetters)
          ..where((tbl) => tbl.queue.equals(queue) & tbl.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    return DeadLetterEntry(
      envelope: Envelope.fromJson(
        (jsonDecode(row.envelope) as Map).cast<String, Object?>(),
      ),
      reason: row.reason,
      meta: row.meta == null
          ? null
          : (jsonDecode(row.meta!) as Map).cast<String, Object?>(),
      deadAt: DateTime.fromMillisecondsSinceEpoch(row.deadAt),
    );
  }

  @override
  Future<DeadLetterReplayResult> replayDeadLetters(
    String queue, {
    int limit = 50,
    DateTime? since,
    Duration? delay,
    bool dryRun = false,
  }) async {
    final sinceMs = since?.millisecondsSinceEpoch;
    final query = (_db.select(_db.stemDeadLetters)
          ..where(
            (tbl) => tbl.queue.equals(queue) &
                (sinceMs == null
                    ? const Constant<bool>(true)
                    : tbl.deadAt.isBiggerOrEqualValue(sinceMs)),
          )
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.deadAt)])
          ..limit(limit));
    final rows = await query.get();
    if (dryRun || rows.isEmpty) {
      return DeadLetterReplayResult(requeued: const [], total: rows.length);
    }

    final requeued = <String>[];
    await _db.transaction(() async {
      for (final row in rows) {
        final envelope = Envelope.fromJson(
          (jsonDecode(row.envelope) as Map).cast<String, Object?>(),
        );
        final updated = delay == null
            ? envelope
            : envelope.copyWith(notBefore: DateTime.now().add(delay));
        await _insertJob(
          envelope: updated,
          queue: queue,
          priority: updated.priority,
          attempt: updated.attempt,
          notBefore: updated.notBefore?.millisecondsSinceEpoch,
        );
        await (_db.delete(_db.stemDeadLetters)
              ..where((tbl) => tbl.id.equals(row.id)))
            .go();
        requeued.add(row.id);
      }
    });

    return DeadLetterReplayResult(requeued: requeued, total: rows.length);
  }

  @override
  Future<int> purgeDeadLetters(
    String queue, {
    DateTime? since,
    int? limit,
  }) async {
    final sinceMs = since?.millisecondsSinceEpoch;
    if (limit != null) {
      final ids = await (_db.select(_db.stemDeadLetters)
            ..where((tbl) => tbl.queue.equals(queue))
            ..orderBy([(tbl) => OrderingTerm.desc(tbl.deadAt)])
            ..limit(limit))
          .map((row) => row.id)
          .get();
      if (ids.isEmpty) return 0;
      await (_db.delete(_db.stemDeadLetters)
            ..where((tbl) => tbl.id.isIn(ids)))
          .go();
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

    return _db.transaction(() async {
      final candidate = await _db.customSelect(
        'SELECT * FROM stem_queue_jobs '
        'WHERE queue = ?1 '
        'AND (not_before IS NULL OR not_before <= ?2) '
        'AND (locked_until IS NULL OR locked_until <= ?2) '
        'ORDER BY priority DESC, created_at ASC LIMIT 1',
        variables: [Variable.withString(queue), Variable.withInt(now)],
        readsFrom: {_db.stemQueueJobs},
      ).getSingleOrNull();
      if (candidate == null) return null;
      final id = candidate.data['id'] as String;
      final updated = await _db.customUpdate(
        'UPDATE stem_queue_jobs SET locked_at = ?2, locked_until = ?3, locked_by = ?4, updated_at = ?5 '
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
        updates: {_db.stemQueueJobs},
      );
      if (updated == 0) return null;
      return _QueuedJob.fromRow(candidate.data);
    });
  }

  void _startSweeper() {
    _sweeper?.cancel();
    _sweeper = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (_closed) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _db.customUpdate(
        'UPDATE stem_queue_jobs '
        'SET locked_at = NULL, locked_until = NULL, locked_by = NULL '
        'WHERE locked_until IS NOT NULL AND locked_until <= ?1',
        variables: [Variable.withInt(now)],
        updates: {_db.stemQueueJobs},
      );
    });
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _sweeper?.cancel();
    for (final consumer in _consumers.toList()) {
      consumer.dispose();
    }
    await _connections.close();
  }

  String _parseReceipt(String receipt) => receipt;

  Future<void> _insertJob({
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
    await _db.into(_db.stemQueueJobs).insertOnConflictUpdate(job);
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

  void start() {
    if (_running) return;
    _running = true;
    _loop();
  }

  void dispose() {
    _running = false;
    if (!controller.isClosed) {
      controller.close();
    }
  }

  Future<void> _loop() async {
    while (_running && !controller.isClosed && !broker._closed) {
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
      final now = DateTime.now();
      for (final job in jobs) {
        if (!_running || controller.isClosed) break;
        final delivery = job.toDelivery(
          leaseExpiresAt: now.add(broker.defaultVisibilityTimeout),
        );
        controller.add(delivery);
      }
    }
  }
}

class _QueuedJob {
  _QueuedJob({
    required this.id,
    required this.queue,
    required this.envelope,
  });

  final String id;
  final String queue;
  final Envelope envelope;

  static _QueuedJob fromRow(Map<String, Object?> row) {
    final envelopeMap = jsonDecode(row['envelope'] as String) as Map;
    return _QueuedJob(
      id: row['id'] as String,
      queue: row['queue'] as String,
      envelope: Envelope.fromJson(envelopeMap.cast<String, Object?>()),
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
