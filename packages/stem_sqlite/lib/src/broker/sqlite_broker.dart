import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:ormed/ormed.dart';
import 'package:stem/stem.dart';
import 'package:stem_sqlite/src/connection.dart';
import 'package:stem_sqlite/src/models/models.dart';
import 'package:uuid/uuid.dart';

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

  /// Creates a broker using an existing [DataSource].
  ///
  /// The caller remains responsible for disposing the [DataSource].
  static Future<SqliteBroker> fromDataSource(
    DataSource dataSource, {
    String namespace = 'stem',
    Duration defaultVisibilityTimeout = const Duration(seconds: 30),
    Duration pollInterval = const Duration(milliseconds: 250),
    Duration sweeperInterval = const Duration(seconds: 10),
    Duration deadLetterRetention = const Duration(days: 7),
  }) async {
    final resolvedNamespace = namespace.trim().isEmpty
        ? 'stem'
        : namespace.trim();
    final connections = await SqliteConnections.openWithDataSource(dataSource);
    return SqliteBroker._(
      connections,
      namespace: resolvedNamespace,
      defaultVisibilityTimeout: defaultVisibilityTimeout,
      pollInterval: pollInterval,
      sweeperInterval: sweeperInterval,
      deadLetterRetention: deadLetterRetention,
    );
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
  // Shared per-isolate to enable in-process fan-out across broker handles
  // using the same namespace.
  static final Map<String, Set<_Consumer>> _broadcastConsumersByChannel = {};
  Timer? _sweeperTimer;
  bool _closed = false;

  @override
  bool get supportsDelayed => true;

  @override
  bool get supportsPriority => true;

  /// Closes the broker and releases any database resources.
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _sweeperTimer?.cancel();
    _sweeperTimer = null;
    for (final consumer in _consumers.toList()) {
      consumer.dispose();
      _consumers.remove(consumer);
    }
    _cleanupBroadcastRegistry();
    await _connections.close();
  }

  /// Runs a maintenance sweep for tests.
  @visibleForTesting
  Future<void> runMaintenance() => _runSweeperCycle();

  @override
  /// Publishes a queued or broadcast envelope.
  ///
  /// Queue routes are persisted to SQLite. Broadcast routes are ephemeral and
  /// are delivered only to active in-process subscribers; if none are active,
  /// the message is dropped.
  Future<void> publish(Envelope envelope, {RoutingInfo? routing}) async {
    final route =
        routing ??
        RoutingInfo.queue(queue: envelope.queue, priority: envelope.priority);
    if (route.isBroadcast) {
      final channel = (route.broadcastChannel ?? envelope.queue).trim();
      if (channel.isEmpty) {
        throw ArgumentError('Broadcast channel must not be empty');
      }
      _fanOutBroadcast(
        channel: channel,
        envelope: envelope.copyWith(queue: channel),
      );
      return;
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
    if (subscription.queues.length > 1) {
      throw UnsupportedError(
        'SqliteBroker currently supports one queue per subscription.',
      );
    }
    final queue = subscription.queues.isEmpty
        ? null
        : subscription.queues.single;
    final broadcastChannels = subscription.broadcastChannels;
    if (queue == null && broadcastChannels.isEmpty) {
      throw ArgumentError(
        'SqliteBroker requires at least one queue or broadcast channel.',
      );
    }
    final id = consumerName ?? const Uuid().v7();
    final controller = StreamController<Delivery>.broadcast();
    final consumer = _Consumer(
      broker: this,
      queue: queue,
      broadcastChannels: broadcastChannels,
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
    if (delivery.route.isBroadcast) {
      return;
    }
    final jobId = _parseReceipt(delivery.receipt);
    await _context
        .query<StemQueueJob>()
        .whereEquals('id', jobId)
        .whereEquals('namespace', namespace)
        .delete();
  }

  @override
  Future<void> nack(Delivery delivery, {bool requeue = true}) async {
    if (delivery.route.isBroadcast) {
      return;
    }
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
    if (delivery.route.isBroadcast) {
      return;
    }
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
    if (delivery.route.isBroadcast) {
      return;
    }
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

  static const String _broadcastReceiptPrefix = 'broadcast:';

  String _parseReceipt(String receipt) => receipt;

  String _broadcastReceipt(String envelopeId, String consumerId) {
    final nowMicros = DateTime.now().microsecondsSinceEpoch;
    return '$_broadcastReceiptPrefix$envelopeId:$consumerId:$nowMicros';
  }

  String _broadcastKey(String channel) => '$namespace:$channel';

  void _registerBroadcastConsumer(_Consumer consumer) {
    for (final channel in consumer.broadcastChannels) {
      final key = _broadcastKey(channel);
      _broadcastConsumersByChannel
          .putIfAbsent(key, () => <_Consumer>{})
          .add(
            consumer,
          );
    }
  }

  void _unregisterBroadcastConsumer(_Consumer consumer) {
    for (final channel in consumer.broadcastChannels) {
      final key = _broadcastKey(channel);
      final consumersForChannel = _broadcastConsumersByChannel[key];
      if (consumersForChannel == null) {
        continue;
      }
      consumersForChannel.remove(consumer);
      if (consumersForChannel.isEmpty) {
        _broadcastConsumersByChannel.remove(key);
      }
    }
  }

  void _fanOutBroadcast({
    required String channel,
    required Envelope envelope,
  }) {
    final consumers = List<_Consumer>.from(
      _broadcastConsumersByChannel[_broadcastKey(channel)] ??
          const <_Consumer>[],
    );
    if (consumers.isEmpty) {
      return;
    }
    final leaseExpiresAt = DateTime.now().add(defaultVisibilityTimeout);
    for (final consumer in consumers) {
      if (!consumer.isActive) {
        continue;
      }
      consumer.enqueueBroadcast(
        Delivery(
          envelope: envelope,
          receipt: _broadcastReceipt(envelope.id, consumer.consumerId),
          leaseExpiresAt: leaseExpiresAt,
          route: RoutingInfo.broadcast(channel: channel),
        ),
      );
    }
  }

  void _cleanupBroadcastRegistry() {
    final keys = _broadcastConsumersByChannel.keys.toList(growable: false);
    for (final key in keys) {
      final consumers = _broadcastConsumersByChannel[key];
      if (consumers == null) {
        continue;
      }
      consumers.removeWhere((consumer) => identical(consumer.broker, this));
      if (consumers.isEmpty) {
        _broadcastConsumersByChannel.remove(key);
      }
    }
  }

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
    required this.broadcastChannels,
    required this.consumerId,
    required this.controller,
    required this.prefetch,
  });

  final SqliteBroker broker;
  final String? queue;
  final List<String> broadcastChannels;
  final String consumerId;
  final StreamController<Delivery> controller;
  final int prefetch;
  final Queue<Delivery> _pendingBroadcast = Queue<Delivery>();
  static const int _maxPendingBroadcast = 1000;

  bool _running = false;
  bool _loopActive = false;
  bool _broadcastRegistered = false;

  bool get isActive => _running && !controller.isClosed;

  void start() {
    if (_running) return;
    _running = true;
    if (!_broadcastRegistered && broadcastChannels.isNotEmpty) {
      broker._registerBroadcastConsumer(this);
      _broadcastRegistered = true;
    }
    if (!_loopActive) {
      _loopActive = true;
      unawaited(_loop());
    }
  }

  void dispose() {
    _running = false;
    if (_broadcastRegistered) {
      broker._unregisterBroadcastConsumer(this);
      _broadcastRegistered = false;
    }
    _pendingBroadcast.clear();
    if (!controller.isClosed) {
      unawaited(controller.close());
    }
  }

  void enqueueBroadcast(Delivery delivery) {
    if (!_running || controller.isClosed) return;
    _pendingBroadcast.addLast(delivery);
    while (_pendingBroadcast.length > _maxPendingBroadcast) {
      _pendingBroadcast.removeFirst();
    }
  }

  bool _drainBroadcast() {
    var emitted = false;
    while (_pendingBroadcast.isNotEmpty && _running && !controller.isClosed) {
      controller.add(_pendingBroadcast.removeFirst());
      emitted = true;
    }
    return emitted;
  }

  Future<void> _loop() async {
    while (_running && !controller.isClosed && !broker._closed) {
      try {
        var emitted = _drainBroadcast();
        final boundQueue = queue;
        if (boundQueue != null) {
          final jobs = <_QueuedJob>[];
          for (var i = 0; i < prefetch; i++) {
            final job = await broker._claimNextJob(boundQueue, consumerId);
            if (job == null) break;
            jobs.add(job);
          }
          if (jobs.isNotEmpty) {
            emitted = true;
            final leaseExpiresAt = DateTime.now().add(
              broker.defaultVisibilityTimeout,
            );
            for (final job in jobs) {
              if (!_running || controller.isClosed) break;
              controller.add(job.toDelivery(leaseExpiresAt: leaseExpiresAt));
            }
          }
        }
        if (!emitted) {
          await Future<void>.delayed(broker.pollInterval);
          continue;
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
