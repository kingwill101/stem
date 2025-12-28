import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:ormed/ormed.dart';
import 'package:stem/stem.dart';

import '../connection.dart';
import '../database/models/models.dart';

class PostgresBroker implements Broker {
  PostgresBroker._(
    this._connections, {
    required this.defaultVisibilityTimeout,
    required this.pollInterval,
    this.sweeperInterval = const Duration(seconds: 10),
    this.deadLetterRetention = const Duration(days: 7),
  })  : _context = _connections.context,
        _random = Random() {
    _startSweeper();
  }

  static Future<PostgresBroker> connect(
    String connectionString, {
    Duration defaultVisibilityTimeout = const Duration(seconds: 30),
    Duration pollInterval = const Duration(milliseconds: 500),
    Duration sweeperInterval = const Duration(seconds: 10),
    Duration deadLetterRetention = const Duration(days: 7),
    String? applicationName,
    TlsConfig? tls,
  }) async {
    final connections = await PostgresConnections.open(
      connectionString: connectionString,
    );
    return PostgresBroker._(
      connections,
      defaultVisibilityTimeout: defaultVisibilityTimeout,
      pollInterval: pollInterval,
      sweeperInterval: sweeperInterval,
      deadLetterRetention: deadLetterRetention,
    );
  }

  final PostgresConnections _connections;
  final QueryContext _context;
  final Duration defaultVisibilityTimeout;
  final Duration pollInterval;
  final Duration sweeperInterval;
  final Duration deadLetterRetention;

  /// Simple async mutex to serialize DB access because the Postgres driver
  /// rejects concurrent work on the same connection while a transaction is
  /// open.
  Future<void> _dbLock = Future.value();

  final Set<_ConsumerRunner> _consumers = {};
  final Random _random;

  Timer? _sweeperTimer;
  bool _closed = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _sweeperTimer?.cancel();
    _sweeperTimer = null;
    for (final runner in List<_ConsumerRunner>.of(_consumers)) {
      runner.stop();
      await runner.controller.close();
    }
    _consumers.clear();
    await _connections.close();
  }

  @override
  bool get supportsDelayed => true;

  @override
  bool get supportsPriority => true;

  Future<T> _withDb<T>(Future<T> Function() action) {
    final run = _dbLock.then((_) => action());
    // Swallow errors on the lock chain so it continues for later callers.
    _dbLock = run.then<void>((_) {}).catchError((_, __) {});
    return run;
  }

  @override
  Future<void> publish(Envelope envelope, {RoutingInfo? routing}) async {
    final resolvedRoute = routing ??
        RoutingInfo.queue(queue: envelope.queue, priority: envelope.priority);

    if (resolvedRoute.isBroadcast) {
      final channel = resolvedRoute.broadcastChannel ?? envelope.queue;
      final message = envelope.copyWith(queue: channel);
      final model = StemBroadcastMessage(
        id: message.id,
        channel: channel,
        envelope: message.toJson(),
        delivery: resolvedRoute.delivery ?? 'at-least-once',
      ).toTracked();
      await _context.repository<StemBroadcastMessage>().upsert(
        model,
        uniqueBy: ['id'],
      );
      return;
    }

    final targetQueue = (resolvedRoute.queue ?? envelope.queue).trim();
    if (targetQueue.isEmpty) {
      throw StateError('Resolved queue must not be empty.');
    }

    final stored = envelope.copyWith(
      queue: targetQueue,
      priority: resolvedRoute.priority ?? envelope.priority,
    );

    await _withDb(() async {
      await _connections.runInTransaction((txn) async {
        await _insertJob(
          txn,
          envelope: stored,
          queue: targetQueue,
          priority: stored.priority,
          attempt: stored.attempt,
          notBefore: stored.notBefore,
        );
      });
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
      throw ArgumentError('RoutingSubscription must specify at least one queue.');
    }
    if (subscription.queues.length > 1) {
      throw UnsupportedError(
        'PostgresBroker currently supports consuming a single queue per subscription.',
      );
    }

    final queue = subscription.queues.first;
    final group = consumerGroup ?? 'default';
    final consumer = consumerName ??
        'pg-consumer-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 16)}';
    final locker = _encodeLocker(queue, group, consumer);
    final broadcastChannels = subscription.broadcastChannels;

    late _ConsumerRunner runner;
    final controller = StreamController<Delivery>.broadcast(
      onListen: () => runner.start(),
      onCancel: () {
        runner.stop();
        _consumers.remove(runner);
      },
    );
    runner = _ConsumerRunner(
      broker: this,
      controller: controller,
      queue: queue,
      locker: locker,
      prefetch: prefetch < 1 ? 1 : prefetch,
      broadcastChannels: broadcastChannels,
      workerId: consumer,
    );
    _consumers.add(runner);
    if (_closed) {
      scheduleMicrotask(() async {
        await controller.close();
      });
    }
    return controller.stream;
  }

  @override
  Future<void> ack(Delivery delivery) async {
    if (delivery.route.isBroadcast) {
      await _ackBroadcast(delivery);
      return;
    }
    final jobId = _parseReceipt(delivery.receipt);
    await _withDb(() {
      return _context
        .query<StemQueueJob>()
        .whereEquals('id', jobId)
        .delete();
    });
  }

  @override
  Future<void> nack(Delivery delivery, {bool requeue = true}) async {
    if (delivery.route.isBroadcast) {
      await _ackBroadcast(delivery);
      return;
    }
    if (!requeue) {
      await deadLetter(delivery, reason: 'nack');
      return;
    }
    final jobId = _parseReceipt(delivery.receipt);
    final now = DateTime.now().toUtc();
    await _withDb(() {
      return _context
          .query<StemQueueJob>()
          .whereEquals('id', jobId)
          .update({
            'lockedAt': null,
            'lockedUntil': null,
            'lockedBy': null,
            'attempt': delivery.envelope.attempt + 1,
            'notBefore': null,
            'updatedAt': now,
          });
    });
  }

  @override
  Future<void> deadLetter(
    Delivery delivery, {
    String? reason,
    Map<String, Object?>? meta,
  }) async {
    if (delivery.route.isBroadcast) {
      await _ackBroadcast(delivery);
      return;
    }
    final jobId = _parseReceipt(delivery.receipt);
    final entryReason = (reason == null || reason.trim().isEmpty)
        ? 'unknown'
        : reason.trim();
    final deadAt = DateTime.now().toUtc();

    await _withDb(() async {
      await _connections.runInTransaction((txn) async {
        final row = await txn
            .query<StemQueueJob>()
            .whereEquals('id', jobId)
            .firstOrNull();
        await txn.query<StemQueueJob>().whereEquals('id', jobId).delete();
        if (row != null) {
          await txn.repository<StemDeadLetter>().upsert(
            StemDeadLetter(
              id: row.id,
              queue: row.queue,
              envelope: row.envelope,
              reason: entryReason,
              meta: meta,
              deadAt: deadAt,
            ).toTracked(),
            uniqueBy: ['id'],
          );
        }
      });
    });
  }

  @override
  Future<void> purge(String queue) async {
    await _withDb(() {
      return _context
          .query<StemQueueJob>()
          .whereEquals('queue', queue)
          .delete();
    });
  }

  @override
  Future<void> extendLease(Delivery delivery, Duration by) async {
    if (by <= Duration.zero) return;
    final jobId = _parseReceipt(delivery.receipt);
    final leaseUntil = DateTime.now().toUtc().add(by);
    await _withDb(() {
      return _context.repository<StemQueueJob>().update(
            StemQueueJobUpdateDto(lockedUntil: leaseUntil),
            where: StemQueueJobPartial(id: jobId),
          );
    });
  }

  @override
  Future<int?> pendingCount(String queue) async {
    final now = DateTime.now().toUtc();
    return _withDb(() {
      return _context
          .query<StemQueueJob>()
          .whereEquals('queue', queue)
          .where((q) {
            q
              ..whereNull('notBefore')
              ..orWhere('notBefore', now, PredicateOperator.lessThanOrEqual);
          })
          .where((q) {
            q
              ..whereNull('lockedUntil')
              ..orWhere('lockedUntil', now, PredicateOperator.lessThanOrEqual);
          })
          .count();
    });
  }

  @override
  Future<int?> inflightCount(String queue) async {
    final now = DateTime.now().toUtc();
    return _withDb(() {
      return _context
        .query<StemQueueJob>()
        .whereEquals('queue', queue)
        .whereNotNull('lockedUntil')
        .where('lockedUntil', now, PredicateOperator.greaterThan)
        .count();
    });
  }

  @override
  Future<DeadLetterPage> listDeadLetters(
    String queue, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (limit <= 0) {
      return const DeadLetterPage(entries: []);
    }
    final normalizedOffset = offset < 0 ? 0 : offset;
    final entries = await _withDb(() async {
      final rows = await _context
          .query<StemDeadLetter>()
          .whereEquals('queue', queue)
          .orderBy('deadAt', descending: true)
          .limit(limit)
          .offset(normalizedOffset)
          .get();
      return rows.map(_deadLetterFromRow).toList(growable: false);
    });
    final nextOffset = entries.length < limit
        ? null
        : normalizedOffset + entries.length;
    return DeadLetterPage(entries: entries, nextOffset: nextOffset);
  }

  @override
  Future<DeadLetterEntry?> getDeadLetter(String queue, String id) async {
    final row = await _withDb(() {
      return _context
        .query<StemDeadLetter>()
        .whereEquals('queue', queue)
        .whereEquals('id', id)
        .firstOrNull();
    });
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
    var query = _context.query<StemDeadLetter>().whereEquals('queue', queue);
    if (since != null) {
      query = query.where('deadAt', since, PredicateOperator.greaterThanOrEqual);
    }
    final rows = await _withDb(() {
      return query.orderBy('deadAt', descending: true).limit(bounded).get();
    });

    final entries = rows.map(_deadLetterFromRow).toList(growable: false);
    if (dryRun || entries.isEmpty) {
      return DeadLetterReplayResult(entries: entries, dryRun: true);
    }

    await _withDb(() async {
      await _connections.runInTransaction((txn) async {
        for (final entry in entries) {
          final updatedEnvelope = delay == null
              ? entry.envelope
              : entry.envelope.copyWith(
                  notBefore: DateTime.now().toUtc().add(delay),
                );
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
              .delete();
        }
      });
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
      final ids = await _withDb(() {
        return _context
            .query<StemDeadLetter>()
            .whereEquals('queue', queue)
            .orderBy('deadAt', descending: true)
            .limit(limit)
            .pluck<String>('id');
      });
      if (ids.isEmpty) return 0;
      await _withDb(() {
        return _context.query<StemDeadLetter>().whereIn('id', ids).delete();
      });
      return ids.length;
    }

    var query = _context.query<StemDeadLetter>().whereEquals('queue', queue);
    if (since != null) {
      query = query.where('deadAt', since, PredicateOperator.greaterThanOrEqual);
    }
    return _withDb(() => query.delete());
  }

  Future<_QueuedJob?> _claimNextJob(String queue, String consumerId) async {
    final now = DateTime.now().toUtc();
    final visibilityUntil = now.add(defaultVisibilityTimeout);

    return _withDb(() {
      return _connections.runInTransaction((txn) async {
      final candidate = await txn
          .query<StemQueueJob>()
          .whereEquals('queue', queue)
          .where((q) {
            q
              ..whereNull('notBefore')
              ..orWhere('notBefore', now, PredicateOperator.lessThanOrEqual);
          })
          .where((q) {
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
          .where((q) {
            q
              ..whereNull('lockedUntil')
              ..orWhere('lockedUntil', now, PredicateOperator.lessThanOrEqual);
          })
          .where((q) {
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
    });
  }

  Future<List<Delivery>> _reserveBroadcast(
    List<String> channels,
    String workerId,
    int limit,
  ) async {
    if (channels.isEmpty) return const <Delivery>[];
    final messages = await _withDb(() {
      return _context
        .query<StemBroadcastMessage>()
        .whereIn('channel', channels)
        .orderBy('createdAt')
        .limit(limit < 1 ? 1 : limit)
        .get();
    });

    final deliveries = <Delivery>[];
    for (final message in messages) {
      final alreadyAcked = await _withDb(() {
        return _context
            .query<StemBroadcastAck>()
            .whereEquals('messageId', message.id)
            .whereEquals('workerId', workerId)
            .exists();
      });
      if (alreadyAcked) continue;
      deliveries.add(
        Delivery(
          envelope: Envelope.fromJson(message.envelope).copyWith(
            queue: message.channel,
          ),
          receipt: jsonEncode({'messageId': message.id, 'worker': workerId}),
          leaseExpiresAt: null,
          route: RoutingInfo.broadcast(
            channel: message.channel,
            delivery: message.delivery,
          ),
        ),
      );
      if (deliveries.length >= limit) break;
    }
    return deliveries;
  }

  Future<void> _ackBroadcast(Delivery delivery) async {
    final data = jsonDecode(delivery.receipt) as Map<String, dynamic>;
    final messageId = data['messageId'] as String;
    final workerId = data['worker'] as String;
    final ack = StemBroadcastAck(
      messageId: messageId,
      workerId: workerId,
      acknowledgedAt: DateTime.now().toUtc(),
    ).toTracked();
    await _withDb(() {
      return _context.repository<StemBroadcastAck>().upsert(
            ack,
            uniqueBy: ['messageId', 'workerId'],
          );
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
    final now = DateTime.now().toUtc();
    await _withDb(() async {
      await _connections.runInTransaction((txn) async {
        await txn
            .query<StemQueueJob>()
            .whereNotNull('lockedUntil')
            .where('lockedUntil', now, PredicateOperator.lessThanOrEqual)
            .update({
              'lockedAt': null,
              'lockedUntil': null,
              'lockedBy': null,
            });

        if (!deadLetterRetention.isNegative &&
            deadLetterRetention > Duration.zero) {
          final cutoff = now.subtract(deadLetterRetention);
          await txn
              .query<StemDeadLetter>()
              .where('deadAt', cutoff, PredicateOperator.lessThanOrEqual)
              .delete();
        }
      });
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
      queue: queue,
      envelope: envelope.toJson(),
      attempt: attempt,
      maxRetries: envelope.maxRetries,
      priority: priority,
      notBefore: notBefore,
      lockedAt: null,
      lockedUntil: null,
      lockedBy: null,
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

  String _encodeLocker(String queue, String group, String consumer) {
    final salt = _random.nextInt(1 << 32);
    return '$queue::$group::$consumer::$salt::${DateTime.now().microsecondsSinceEpoch}';
  }
}

class _ConsumerRunner {
  _ConsumerRunner({
    required this.broker,
    required this.controller,
    required this.queue,
    required this.locker,
    required this.prefetch,
    required this.broadcastChannels,
    required this.workerId,
  });

  final PostgresBroker broker;
  final StreamController<Delivery> controller;
  final String queue;
  final String locker;
  final int prefetch;
  final List<String> broadcastChannels;
  final String workerId;

  bool _started = false;
  bool _stopped = false;

  void start() {
    if (_started) return;
    _started = true;
    _loop();
  }

  void stop() {
    _stopped = true;
  }

  Future<void> _loop() async {
    while (!_stopped && !controller.isClosed && !broker._closed) {
      try {
        final jobs = <_QueuedJob>[];
        for (var i = 0; i < prefetch; i++) {
          final job = await broker._claimNextJob(queue, locker);
          if (job == null) break;
          jobs.add(job);
        }
        final broadcasts = broadcastChannels.isEmpty
            ? const <Delivery>[]
            : await broker._reserveBroadcast(
                broadcastChannels,
                workerId,
                prefetch,
              );
        if (jobs.isEmpty && broadcasts.isEmpty) {
          await Future.delayed(broker.pollInterval);
          continue;
        }
        final leaseExpiresAt = DateTime.now().toUtc().add(
          broker.defaultVisibilityTimeout,
        );
        for (final delivery in [
          ...jobs.map((job) => job.toDelivery(leaseExpiresAt: leaseExpiresAt)),
          ...broadcasts,
        ]) {
          if (_stopped || controller.isClosed) {
            return;
          }
          controller.add(delivery);
        }
      } catch (error, stack) {
        if (controller.isClosed) return;
        controller.addError(error, stack);
        await Future.delayed(broker.pollInterval);
      }
    }
  }
}

class _QueuedJob {
  _QueuedJob({required this.id, required this.queue, required this.envelope});

  final String id;
  final String queue;
  final Envelope envelope;

  factory _QueuedJob.fromModel(StemQueueJob row) {
    return _QueuedJob(
      id: row.id,
      queue: row.queue,
      envelope: Envelope.fromJson(row.envelope),
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
