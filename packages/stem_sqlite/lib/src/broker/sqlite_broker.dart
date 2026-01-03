import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:ormed/ormed.dart';
import 'package:stem/stem.dart';

import 'package:stem_sqlite/src/connection.dart';
import 'package:stem_sqlite/src/models/models.dart';

/// SQLite-backed implementation of [Broker].
class SqliteBroker implements Broker {
  SqliteBroker._(
    this._connections, {
    required this.namespace,
    required this.defaultVisibilityTimeout,
    required this.pollInterval,
    required this.sweeperInterval,
    required this.deadLetterRetention,
  }) : _context = _connections.context {
    _startSweeper();
  }

  /// Opens a broker backed by the provided SQLite [file].
  static Future<SqliteBroker> open(
    File file, {
    String namespace = 'stem',
    Duration defaultVisibilityTimeout = const Duration(seconds: 30),
    Duration pollInterval = const Duration(milliseconds: 250),
    Duration sweeperInterval = const Duration(seconds: 10),
    Duration deadLetterRetention = const Duration(days: 7),
  }) async {
    final resolvedNamespace = namespace.trim().isEmpty
        ? 'stem'
        : namespace.trim();
    final connections = await SqliteConnections.open(file);
    return SqliteBroker._(
      connections,
      namespace: resolvedNamespace,
      defaultVisibilityTimeout: defaultVisibilityTimeout,
      pollInterval: pollInterval,
      sweeperInterval: sweeperInterval,
      deadLetterRetention: deadLetterRetention,
    );
  }

  final SqliteConnections _connections;
  final QueryContext _context;

  /// Namespace used to scope broker data.
  final String namespace;

  /// Default visibility timeout applied to deliveries.
  final Duration defaultVisibilityTimeout;

  /// Poll interval used while waiting for jobs.
  final Duration pollInterval;

  /// Interval used to sweep for expired locks.
  final Duration sweeperInterval;

  /// Retention window for dead letter records.
  final Duration deadLetterRetention;

  final Set<_Consumer> _consumers = {};
  Timer? _sweeperTimer;
  bool _closed = false;

  @override
  bool get supportsDelayed => true;

  @override
  bool get supportsPriority => true;

  /// Closes the broker and releases any database resources.
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

  /// Runs a maintenance sweep for tests.
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
        notBefore: stored.notBefore,
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
        'sqlite-consumer-${DateTime.now().microsecondsSinceEpoch}-'
            '${_consumers.length}';
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
    await _context
        .query<StemQueueJob>()
        .whereEquals('id', jobId)
        .whereEquals('namespace', namespace)
        .delete();
  }

  @override
  Future<void> nack(Delivery delivery, {bool requeue = true}) async {
    if (!requeue) {
      await deadLetter(delivery, reason: 'nack');
      return;
    }
    final jobId = _parseReceipt(delivery.receipt);
    final now = DateTime.now();
    await _context
        .query<StemQueueJob>()
        .whereEquals('id', jobId)
        .whereEquals('namespace', namespace)
        .update({
          'lockedAt': null,
          'lockedUntil': null,
          'lockedBy': null,
          'attempt': delivery.envelope.attempt + 1,
          'notBefore': null,
          'updatedAt': now,
        });
  }

  @override
  Future<void> deadLetter(
    Delivery delivery, {
    String? reason,
    Map<String, Object?>? meta,
  }) async {
    final jobId = _parseReceipt(delivery.receipt);
    final now = DateTime.now();

    final row = await _context
        .query<StemQueueJob>()
        .whereEquals('id', jobId)
        .whereEquals('namespace', namespace)
        .firstOrNull();
    await _context
        .query<StemQueueJob>()
        .whereEquals('id', jobId)
        .whereEquals('namespace', namespace)
        .delete();
    if (row != null) {
      await _context.repository<StemDeadLetter>().insert(
        StemDeadLetterInsertDto(
          id: row.id,
          namespace: namespace,
          queue: row.queue,
          envelope: row.envelope,
          reason: reason,
          meta: meta,
          deadAt: now,
        ),
      );
    }
  }

  @override
  Future<void> extendLease(Delivery delivery, Duration by) async {
    final jobId = _parseReceipt(delivery.receipt);
    final now = DateTime.now();
    await _context.repository<StemQueueJob>().update(
      StemQueueJobUpdateDto(lockedUntil: now.add(by)),
      where: StemQueueJobPartial(id: jobId, namespace: namespace),
    );
  }

  @override
  Future<void> purge(String queue) async {
    await _context
        .query<StemQueueJob>()
        .whereEquals('queue', queue)
        .whereEquals('namespace', namespace)
        .delete();
  }

  @override
  Future<int?> pendingCount(String queue) async {
    final now = DateTime.now();
    return _context
        .query<StemQueueJob>()
        .whereEquals('queue', queue)
        .whereEquals('namespace', namespace)
        .where((PredicateBuilder<StemQueueJob> query) {
          query
            ..whereNull('notBefore')
            ..orWhere('notBefore', now, PredicateOperator.lessThanOrEqual);
        })
        .where((PredicateBuilder<StemQueueJob> query) {
          query
            ..whereNull('lockedUntil')
            ..orWhere('lockedUntil', now, PredicateOperator.lessThanOrEqual);
        })
        .count();
  }

  @override
  Future<int?> inflightCount(String queue) async {
    final now = DateTime.now();
    return _context
        .query<StemQueueJob>()
        .whereEquals('queue', queue)
        .whereEquals('namespace', namespace)
        .whereNotNull('lockedUntil')
        .where('lockedUntil', now, PredicateOperator.greaterThan)
        .count();
  }

  @override
  Future<DeadLetterPage> listDeadLetters(
    String queue, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (limit <= 0) return const DeadLetterPage(entries: []);
    final entries = await _context
        .query<StemDeadLetter>()
        .whereEquals('queue', queue)
        .whereEquals('namespace', namespace)
        .orderBy('deadAt', descending: true)
        .limit(limit)
        .offset(offset)
        .get()
        .then((rows) => rows.map(_deadLetterFromRow).toList(growable: false));
    final nextOffset = entries.length < limit ? null : offset + limit;
    return DeadLetterPage(entries: entries, nextOffset: nextOffset);
  }

  @override
  Future<DeadLetterEntry?> getDeadLetter(String queue, String id) async {
    final row = await _context
        .query<StemDeadLetter>()
        .whereEquals('queue', queue)
        .whereEquals('id', id)
        .whereEquals('namespace', namespace)
        .firstOrNull();
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
    var query = _context
        .query<StemDeadLetter>()
        .whereEquals('queue', queue)
        .whereEquals('namespace', namespace);
    if (since != null) {
      query = query.where(
        'deadAt',
        since,
        PredicateOperator.greaterThanOrEqual,
      );
    }
    final rows = await query
        .orderBy('deadAt', descending: true)
        .limit(bounded)
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
          notBefore: updatedEnvelope.notBefore,
        );
        await txn
            .query<StemDeadLetter>()
            .whereEquals('id', entry.envelope.id)
            .whereEquals('namespace', namespace)
            .delete();
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
    if (limit != null) {
      final ids = await _context
          .query<StemDeadLetter>()
          .whereEquals('queue', queue)
          .whereEquals('namespace', namespace)
          .orderBy('deadAt', descending: true)
          .limit(limit)
          .pluck<String>('id');
      if (ids.isEmpty) return 0;
      await _context
          .query<StemDeadLetter>()
          .whereIn('id', ids)
          .whereEquals('namespace', namespace)
          .delete();
      return ids.length;
    }

    var query = _context
        .query<StemDeadLetter>()
        .whereEquals('queue', queue)
        .whereEquals('namespace', namespace);
    if (since != null) {
      query = query.where(
        'deadAt',
        since,
        PredicateOperator.greaterThanOrEqual,
      );
    }
    return query.delete();
  }

  Future<_QueuedJob?> _claimNextJob(String queue, String consumerId) async {
    final now = DateTime.now();
    final visibilityUntil = now.add(defaultVisibilityTimeout);

    return _connections.runInTransaction((txn) async {
      final candidate = await txn
          .query<StemQueueJob>()
          .whereEquals('queue', queue)
          .whereEquals('namespace', namespace)
          .where((PredicateBuilder<StemQueueJob> q) {
            q
              ..whereNull('notBefore')
              ..orWhere('notBefore', now, PredicateOperator.lessThanOrEqual);
          })
          .where((PredicateBuilder<StemQueueJob> q) {
            q
              ..whereNull('lockedUntil')
              ..orWhere('lockedUntil', now, PredicateOperator.lessThanOrEqual);
          })
          .orderBy('priority', descending: true)
          .orderBy('createdAt')
          .limit(1)
          .firstOrNull();
      if (candidate == null) return null;

      final updated = await txn
          .query<StemQueueJob>()
          .whereEquals('id', candidate.id)
          .whereEquals('namespace', namespace)
          .where((PredicateBuilder<StemQueueJob> q) {
            q
              ..whereNull('lockedUntil')
              ..orWhere('lockedUntil', now, PredicateOperator.lessThanOrEqual);
          })
          .where((PredicateBuilder<StemQueueJob> q) {
            q
              ..whereNull('notBefore')
              ..orWhere('notBefore', now, PredicateOperator.lessThanOrEqual);
          })
          .update({
            'lockedAt': now,
            'lockedUntil': visibilityUntil,
            'lockedBy': consumerId,
            'updatedAt': now,
          });
      if (updated == 0) return null;
      return _QueuedJob.fromModel(candidate);
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
    final now = DateTime.now();
    await _connections.runInTransaction((txn) async {
      await txn
          .query<StemQueueJob>()
          .whereEquals('namespace', namespace)
          .whereNotNull('lockedUntil')
          .where('lockedUntil', now, PredicateOperator.lessThanOrEqual)
          .update({'lockedAt': null, 'lockedUntil': null, 'lockedBy': null});

      if (!deadLetterRetention.isNegative &&
          deadLetterRetention > Duration.zero) {
        final cutoff = now.subtract(deadLetterRetention);
        await txn
            .query<StemDeadLetter>()
            .whereEquals('namespace', namespace)
            .where('deadAt', cutoff, PredicateOperator.lessThanOrEqual)
            .delete();
      }
    });
  }

  String _parseReceipt(String receipt) => receipt;

  Future<void> _insertJob(
    QueryContext db, {
    required Envelope envelope,
    required String queue,
    required int priority,
    required int attempt,
    DateTime? notBefore,
  }) async {
    final model = StemQueueJob(
      id: envelope.id,
      namespace: namespace,
      queue: queue,
      envelope: envelope.toJson(),
      attempt: attempt,
      maxRetries: envelope.maxRetries,
      priority: priority,
      notBefore: notBefore,
    ).toTracked();
    await db.repository<StemQueueJob>().upsert(model, uniqueBy: ['id']);
  }

  DeadLetterEntry _deadLetterFromRow(StemDeadLetter row) {
    final envelope = Envelope.fromJson(row.envelope);
    return DeadLetterEntry(
      envelope: envelope,
      reason: row.reason,
      meta: row.meta,
      deadAt: row.deadAt,
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
      } on Object {
        if (!_running || controller.isClosed) break;
        await Future<void>.delayed(broker.pollInterval);
      }
    }
    _loopActive = false;
  }
}

class _QueuedJob {
  _QueuedJob({required this.id, required this.queue, required this.envelope});

  factory _QueuedJob.fromModel(StemQueueJob row) {
    return _QueuedJob(
      id: row.id,
      queue: row.queue,
      envelope: Envelope.fromJson(row.envelope),
    );
  }

  final String id;
  final String queue;
  final Envelope envelope;

  Delivery toDelivery({required DateTime leaseExpiresAt}) {
    return Delivery(
      envelope: envelope,
      receipt: id,
      leaseExpiresAt: leaseExpiresAt,
      route: RoutingInfo.queue(queue: queue, priority: envelope.priority),
    );
  }
}
