import 'dart:async';
import 'dart:convert';

import 'package:ormed/ormed.dart';
import 'package:stem/observability.dart' show stemLogger;
import 'package:stem/stem.dart';
import 'package:stem_postgres/src/connection.dart';
import 'package:stem_postgres/src/database/models/models.dart';
import 'package:stem_postgres/src/observability/postgres_timing.dart';
import 'package:uuid/uuid.dart';

/// PostgreSQL-backed implementation of [Broker].
class PostgresBroker
    implements
        Broker,
        LeaseBroker,
        InspectableBroker,
        DeadLetterBroker,
        BrokerCapabilitiesProvider {
  PostgresBroker._(
    this._connections, {
    required this.namespace,
    required this.defaultVisibilityTimeout,
    required this.pollInterval,
    this.sweeperInterval = const Duration(seconds: 10),
    this.deadLetterRetention = const Duration(days: 7),
    this._consumerConnections,
    this._timingListener,
  }) {
    stemLogger.info(
      'PostgresBroker created (namespace=$namespace)',
      fields: _logContext(),
    );
    _startSweeper();
  }

  /// Creates a broker using an existing [DataSource].
  ///
  /// The caller remains responsible for disposing the [DataSource].
  static Future<PostgresBroker> fromDataSource(
    DataSource dataSource, {
    String namespace = 'stem',
    Duration defaultVisibilityTimeout = const Duration(seconds: 30),
    Duration pollInterval = const Duration(milliseconds: 500),
    Duration sweeperInterval = const Duration(seconds: 10),
    Duration deadLetterRetention = const Duration(days: 7),
    bool runMigrations = true,
    PostgresTimingListener? timingListener,
    PostgresQueryTimingListener? queryTimingListener,
  }) async {
    final resolvedNamespace = namespace.trim().isEmpty
        ? 'stem'
        : namespace.trim();
    final connections = await PostgresConnections.openWithDataSource(
      dataSource,
      runMigrations: runMigrations,
      component: 'broker',
      timingListener: timingListener,
      queryTimingListener: queryTimingListener,
    );
    return PostgresBroker._(
      connections,
      namespace: resolvedNamespace,
      defaultVisibilityTimeout: defaultVisibilityTimeout,
      pollInterval: pollInterval,
      sweeperInterval: sweeperInterval,
      deadLetterRetention: deadLetterRetention,
      timingListener: timingListener,
    );
  }

  /// Connects to PostgreSQL and returns a broker instance.
  ///
  /// By default, publishing and consuming share one PostgreSQL connection,
  /// preserving the connection behavior of earlier releases. Set
  /// [separateConsumerConnection] to `true` when consuming must be isolated
  /// from publisher work; this opens a second connection using the
  /// `broker.consumer` timing component. [fromDataSource] never creates that
  /// second connection because it does not own an independent data source.
  static Future<PostgresBroker> connect(
    String connectionString, {
    String namespace = 'stem',
    Duration defaultVisibilityTimeout = const Duration(seconds: 30),
    Duration pollInterval = const Duration(milliseconds: 500),
    Duration sweeperInterval = const Duration(seconds: 10),
    Duration deadLetterRetention = const Duration(days: 7),
    String? applicationName,
    TlsConfig? tls,
    PostgresTimingListener? timingListener,
    PostgresQueryTimingListener? queryTimingListener,
    bool separateConsumerConnection = false,
  }) async {
    final resolvedNamespace = namespace.trim().isEmpty
        ? 'stem'
        : namespace.trim();
    final connections = await PostgresConnections.open(
      connectionString: connectionString,
      component: 'broker',
      timingListener: timingListener,
      queryTimingListener: queryTimingListener,
    );
    PostgresConnections? consumerConnections;
    try {
      if (separateConsumerConnection) {
        consumerConnections = await PostgresConnections.open(
          connectionString: connectionString,
          component: 'broker.consumer',
          timingListener: timingListener,
          queryTimingListener: queryTimingListener,
        );
      }
      return PostgresBroker._(
        connections,
        namespace: resolvedNamespace,
        defaultVisibilityTimeout: defaultVisibilityTimeout,
        pollInterval: pollInterval,
        sweeperInterval: sweeperInterval,
        deadLetterRetention: deadLetterRetention,
        consumerConnections: consumerConnections,
        timingListener: timingListener,
      );
    } on Object {
      await consumerConnections?.close();
      await connections.close();
      rethrow;
    }
  }

  final PostgresConnections _connections;
  final PostgresConnections? _consumerConnections;
  QueryContext get _context => _connections.context;

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

  final PostgresTimingListener? _timingListener;

  /// Simple async mutex to serialize DB access because the Postgres driver
  /// rejects concurrent work on the same connection while a transaction is
  /// open.
  Future<void> _dbLock = Future.value();
  Future<void> _consumerDbLock = Future.value();

  final Set<_ConsumerRunner> _consumers = {};

  Timer? _sweeperTimer;
  bool _closed = false;
  StackTrace? _closedStack;

  /// Closes the broker and releases any database resources.
  @override
  Future<void> close() async {
    if (_closed) return;
    _closedStack = StackTrace.current;
    stemLogger.warning(
      'Closing PostgresBroker (namespace=$namespace) '
      'stack=${_closedStack ?? ''}',
      fields: _logContext({'stack': _closedStack.toString()}),
    );
    _closed = true;
    _sweeperTimer?.cancel();
    _sweeperTimer = null;
    for (final runner in List<_ConsumerRunner>.of(_consumers)) {
      runner.stop();
      if (runner.controller.hasListener) {
        await runner.controller.close();
      } else {
        unawaited(runner.controller.close());
      }
    }
    _consumers.clear();
    await _dbLock.catchError((_, _) {});
    await _consumerDbLock.catchError((_, _) {});
    await _consumerConnections?.close();
    await _connections.close();
  }

  @override
  bool get supportsDelayed => true;

  @override
  bool get supportsPriority => true;

  @override
  BrokerCapabilities get capabilities => const BrokerCapabilities(
    supportsDelayedDelivery: true,
    supportsPriorityOrdering: true,
    deliveryGuarantee: BrokerDeliveryGuarantee.atLeastOnce,
    supportsQueueInspection: true,
    supportsLeaseExtension: true,
    supportsDeadLettering: true,
    supportsDeadLetterReplay: true,
  );

  Future<T> _withDb<T>(
    Future<T> Function() action, {
    String operation = 'broker.operation',
    bool consumer = false,
  }) {
    final consumerConnections = _consumerConnections;
    final isolatedConsumer = consumer && consumerConnections != null;
    final connections = isolatedConsumer ? consumerConnections : _connections;
    final lock = isolatedConsumer ? _consumerDbLock : _dbLock;
    final component = isolatedConsumer ? 'broker.consumer' : 'broker';
    final listener = _timingListener;
    final queued = listener == null ? null : (Stopwatch()..start());
    final run = lock.then((_) async {
      final queueWait = queued?.elapsed ?? Duration.zero;
      final execution = listener == null ? null : (Stopwatch()..start());
      try {
        await connections.ensureReady();
        final result = await action();
        _notifyTiming(
          component: component,
          operation: operation,
          queueWait: queueWait,
          execution: execution?.elapsed ?? Duration.zero,
          total: queued?.elapsed ?? Duration.zero,
          succeeded: true,
        );
        return result;
      } on Object catch (error) {
        final message = error.toString();
        if (message.contains('already been closed') ||
            message.contains('not been initialized')) {
          try {
            await connections.ensureReady(forceReopen: true);
            final result = await action();
            _notifyTiming(
              component: component,
              operation: operation,
              queueWait: queueWait,
              execution: execution?.elapsed ?? Duration.zero,
              total: queued?.elapsed ?? Duration.zero,
              succeeded: true,
            );
            return result;
          } on Object catch (retryError) {
            _notifyTiming(
              component: component,
              operation: operation,
              queueWait: queueWait,
              execution: execution?.elapsed ?? Duration.zero,
              total: queued?.elapsed ?? Duration.zero,
              succeeded: false,
              error: retryError.toString(),
            );
            rethrow;
          }
        }
        _notifyTiming(
          component: component,
          operation: operation,
          queueWait: queueWait,
          execution: execution?.elapsed ?? Duration.zero,
          total: queued?.elapsed ?? Duration.zero,
          succeeded: false,
          error: error.toString(),
        );
        rethrow;
      }
    });
    // Swallow errors on the lock chain so it continues for later callers.
    final nextLock = run.then<void>((_) {}).catchError((_, _) {});
    if (isolatedConsumer) {
      _consumerDbLock = nextLock;
    } else {
      _dbLock = nextLock;
    }
    return run;
  }

  void _notifyTiming({
    required String component,
    required String operation,
    required Duration queueWait,
    required Duration execution,
    required Duration total,
    required bool succeeded,
    String? error,
  }) {
    final listener = _timingListener;
    if (listener == null) return;
    try {
      listener(
        PostgresOperationTiming(
          component: component,
          operation: operation,
          queueWait: queueWait,
          execution: execution,
          total: total,
          succeeded: succeeded,
          error: error,
        ),
      );
    } on Object {
      // Instrumentation must never change database behavior.
    }
  }

  @override
  Future<void> publish(Envelope envelope, {RoutingInfo? routing}) async {
    final resolvedRoute =
        routing ??
        RoutingInfo.queue(queue: envelope.queue, priority: envelope.priority);

    if (resolvedRoute.isBroadcast) {
      final channel = resolvedRoute.broadcastChannel ?? envelope.queue;
      final message = envelope.copyWith(queue: channel);
      final model = StemBroadcastMessage(
        id: message.id,
        namespace: namespace,
        channel: channel,
        envelope: message.toJson(),
        delivery: resolvedRoute.delivery ?? 'at-least-once',
      ).toTracked();
      await _withDb(
        () => _context.repository<StemBroadcastMessage>().upsert(
          model,
          uniqueBy: ['id'],
        ),
        operation: 'broker.publish',
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

    await _withDb(
      () async {
        await _connections.runInTransaction(
          (txn) async {
            await _insertJob(
              txn,
              envelope: stored,
              queue: targetQueue,
              priority: stored.priority,
              attempt: stored.attempt,
              notBefore: stored.notBefore,
            );
          },
          operation: 'broker.publish.transaction',
        );
      },
      operation: 'broker.publish',
    );
  }

  @override
  Stream<Delivery> consume(
    RoutingSubscription subscription, {
    int prefetch = 1,
    String? consumerGroup,
    String? consumerName,
  }) {
    stemLogger.debug(
      'Broker consume requested (namespace=$namespace, '
      'queues=${subscription.queues})',
      fields: _logContext({'queues': subscription.queues}),
    );
    if (subscription.queues.length > 1) {
      throw UnsupportedError(
        'PostgresBroker currently supports consuming a single queue per '
        'subscription.',
      );
    }

    final queue = subscription.queues.isEmpty
        ? null
        : subscription.queues.single;
    final group = consumerGroup ?? 'default';
    final consumer = consumerName ?? const Uuid().v7();
    final broadcastChannels = subscription.broadcastChannels;
    if (queue == null && broadcastChannels.isEmpty) {
      throw ArgumentError(
        'PostgresBroker requires at least one queue or broadcast channel.',
      );
    }
    final locker = _encodeLocker(queue ?? '__broadcast__', group, consumer);

    late _ConsumerRunner runner;
    late StreamController<Delivery> controller;
    controller = StreamController<Delivery>(
      onListen: () => runner.start(),
      onCancel: () {
        final queueLabel = queue ?? '<broadcast-only>';
        stemLogger.debug(
          'Consumer stream canceled (queue=$queueLabel, worker=$consumer)',
          fields: _logContext({
            'queue': queueLabel,
            'worker': consumer,
          }),
        );
        runner.stop();
        _consumers.remove(runner);
        if (!controller.isClosed) {
          unawaited(controller.close());
        }
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
      stemLogger.warning(
        'Broker already closed; closing consumer stream. '
        'stack=${_closedStack ?? StackTrace.current}',
        fields: _logContext({
          'stack': (_closedStack ?? StackTrace.current).toString(),
        }),
      );
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
    stemLogger.debug(
      'Ack queue job $jobId (${delivery.envelope.queue})',
      fields: _logContext({
        'jobId': jobId,
        'queue': delivery.envelope.queue,
      }),
    );
    final ackConnections = _consumerConnections ?? _connections;
    await _withDb(
      () {
        // Ack does not need the model-loading behavior of Query.delete().
        // deleteWhere compiles directly to a DELETE and avoids an extra SELECT.
        return ackConnections.context.query<StemQueueJob>().deleteWhere({
          'id': jobId,
          'namespace': namespace,
        });
      },
      operation: 'broker.ack',
      consumer: _consumerConnections != null,
    );
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
    stemLogger.debug(
      'Nack queue job $jobId (${delivery.envelope.queue})',
      fields: _logContext({
        'jobId': jobId,
        'queue': delivery.envelope.queue,
      }),
    );
    final now = stemNow().toUtc();
    final consumerConnections = _consumerConnections ?? _connections;
    await _withDb(
      () {
        return consumerConnections.context
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
      },
      operation: 'broker.nack',
      consumer: _consumerConnections != null,
    );
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
    final deadAt = stemNow().toUtc();
    final consumerConnections = _consumerConnections ?? _connections;

    await _withDb(
      () async {
        await consumerConnections.runInTransaction((txn) async {
          final row = await txn
              .query<StemQueueJob>()
              .whereEquals('id', jobId)
              .whereEquals('namespace', namespace)
              .firstOrNull();
          await txn
              .query<StemQueueJob>()
              .whereEquals('id', jobId)
              .whereEquals('namespace', namespace)
              .delete();
          if (row != null) {
            await txn.repository<StemDeadLetter>().upsert(
              StemDeadLetter(
                id: row.id,
                namespace: namespace,
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
      },
      operation: 'broker.dead_letter',
      consumer: _consumerConnections != null,
    );
  }

  @override
  Future<void> purge(String queue) async {
    await _withDb(() {
      return _context
          .query<StemQueueJob>()
          .whereEquals('queue', queue)
          .whereEquals('namespace', namespace)
          .delete();
    });
  }

  @override
  Future<void> extendLease(Delivery delivery, Duration by) async {
    if (by <= Duration.zero) return;
    final jobId = _parseReceipt(delivery.receipt);
    final leaseUntil = stemNow().toUtc().add(by);
    final consumerConnections = _consumerConnections ?? _connections;
    await _withDb(
      () {
        return consumerConnections.context.repository<StemQueueJob>().update(
          StemQueueJobUpdateDto(lockedUntil: leaseUntil),
          where: StemQueueJobPartial(id: jobId, namespace: namespace),
        );
      },
      operation: 'broker.extend_lease',
      consumer: _consumerConnections != null,
    );
  }

  @override
  Future<int?> pendingCount(String queue) async {
    final now = stemNow().toUtc();
    return _withDb(() {
      return _context
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
          .count();
    });
  }

  @override
  Future<int?> inflightCount(String queue) async {
    final now = stemNow().toUtc();
    return _withDb(() {
      return _context
          .query<StemQueueJob>()
          .whereEquals('queue', queue)
          .whereEquals('namespace', namespace)
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
          .whereEquals('namespace', namespace)
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
          .whereEquals('namespace', namespace)
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
                  notBefore: stemNow().toUtc().add(delay),
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
              .whereEquals('namespace', namespace)
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
            .whereEquals('namespace', namespace)
            .orderBy('deadAt', descending: true)
            .limit(limit)
            .pluck<String>('id');
      });
      if (ids.isEmpty) return 0;
      await _withDb(() {
        return _context
            .query<StemDeadLetter>()
            .whereIn('id', ids)
            .whereEquals('namespace', namespace)
            .delete();
      });
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
    return _withDb(() => query.delete());
  }

  Future<_QueuedJob?> _claimNextJob(String queue, String consumerId) async {
    final now = stemNow().toUtc();
    final visibilityUntil = now.add(defaultVisibilityTimeout);
    final claimConnections = _consumerConnections ?? _connections;

    return _withDb(
      () {
        return claimConnections.runInTransaction(
          (txn) async {
            final candidate = await txn
                .query<StemQueueJob>()
                .whereEquals('queue', queue)
                .whereEquals('namespace', namespace)
                .where((PredicateBuilder<StemQueueJob> q) {
                  q
                    ..whereNull('notBefore')
                    ..orWhere(
                      'notBefore',
                      now,
                      PredicateOperator.lessThanOrEqual,
                    );
                })
                .where((PredicateBuilder<StemQueueJob> q) {
                  q
                    ..whereNull('lockedUntil')
                    ..orWhere(
                      'lockedUntil',
                      now,
                      PredicateOperator.lessThanOrEqual,
                    );
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
                    ..orWhere(
                      'lockedUntil',
                      now,
                      PredicateOperator.lessThanOrEqual,
                    );
                })
                .where((PredicateBuilder<StemQueueJob> q) {
                  q
                    ..whereNull('notBefore')
                    ..orWhere(
                      'notBefore',
                      now,
                      PredicateOperator.lessThanOrEqual,
                    );
                })
                .update({
                  'lockedAt': now,
                  'lockedUntil': visibilityUntil,
                  'lockedBy': consumerId,
                  'updatedAt': now,
                });
            if (updated == 0) return null;
            stemLogger.debug(
              'Claimed queue job ${candidate.id} ($queue) by $consumerId',
              fields: _logContext({
                'jobId': candidate.id,
                'queue': queue,
                'worker': consumerId,
              }),
            );
            return _QueuedJob.fromModel(candidate);
          },
          operation: 'broker.claim.transaction',
        );
      },
      operation: 'broker.claim',
      consumer: _consumerConnections != null,
    );
  }

  Future<List<Delivery>> _reserveBroadcast(
    List<String> channels,
    String workerId,
    int limit,
  ) async {
    if (channels.isEmpty) return const <Delivery>[];
    final broadcastConnections = _consumerConnections ?? _connections;
    final isolatedConsumer = _consumerConnections != null;
    final messages = await _withDb(
      () {
        return broadcastConnections.context
            .query<StemBroadcastMessage>()
            .whereEquals('namespace', namespace)
            .whereIn('channel', channels)
            .orderBy('createdAt')
            .limit(limit < 1 ? 1 : limit)
            .get();
      },
      operation: 'broker.broadcast.reserve',
      consumer: isolatedConsumer,
    );

    final deliveries = <Delivery>[];
    for (final message in messages) {
      final alreadyAcked = await _withDb(
        () {
          return broadcastConnections.context
              .query<StemBroadcastAck>()
              .whereEquals('messageId', message.id)
              .whereEquals('workerId', workerId)
              .whereEquals('namespace', namespace)
              .exists();
        },
        operation: 'broker.broadcast.check_ack',
        consumer: isolatedConsumer,
      );
      if (alreadyAcked) continue;
      deliveries.add(
        Delivery(
          envelope: Envelope.fromJson(
            message.envelope,
          ).copyWith(queue: message.channel),
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
      namespace: namespace,
      acknowledgedAt: stemNow().toUtc(),
    ).toTracked();
    final broadcastConnections = _consumerConnections ?? _connections;
    await _withDb(
      () {
        return broadcastConnections.context
            .repository<StemBroadcastAck>()
            .upsert(
              ack,
              uniqueBy: ['messageId', 'workerId'],
            );
      },
      operation: 'broker.broadcast.ack',
      consumer: _consumerConnections != null,
    );
  }

  void _startSweeper() {
    _sweeperTimer?.cancel();
    _sweeperTimer = Timer.periodic(sweeperInterval, (_) {
      if (_closed) return;
      unawaited(_runSweeperCycle());
    });
  }

  Future<void> _runSweeperCycle() async {
    final now = stemNow().toUtc();
    await _withDb(() async {
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
    });
  }

  Map<String, Object?> _logContext([
    Map<String, Object?> fields = const {},
  ]) {
    return {
      'component': 'stem_postgres',
      'subsystem': 'broker',
      'namespace': namespace,
      ...fields,
    };
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

  String _encodeLocker(String queue, String group, String consumer) {
    return '$queue::$group::$consumer::${const Uuid().v7()}';
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
  final String? queue;
  final String locker;
  final int prefetch;
  final List<String> broadcastChannels;
  final String workerId;

  bool _started = false;
  bool _stopped = false;

  void start() {
    if (_started) return;
    _started = true;
    final queueLabel = queue ?? '<broadcast-only>';
    stemLogger.debug(
      'Consumer runner started (queue=$queueLabel, worker=$workerId)',
      fields: broker._logContext({'queue': queueLabel, 'worker': workerId}),
    );
    unawaited(_loop());
  }

  void stop() {
    final queueLabel = queue ?? '<broadcast-only>';
    stemLogger.debug(
      'Consumer runner stopped (queue=$queueLabel, worker=$workerId)',
      fields: broker._logContext({'queue': queueLabel, 'worker': workerId}),
    );
    _stopped = true;
  }

  Future<void> _loop() async {
    while (!_stopped &&
        controller.hasListener &&
        !controller.isClosed &&
        !broker._closed) {
      try {
        final jobs = <_QueuedJob>[];
        if (queue != null) {
          for (var i = 0; i < prefetch; i++) {
            final job = await broker._claimNextJob(queue!, locker);
            if (job == null) break;
            jobs.add(job);
          }
        }
        final broadcasts = broadcastChannels.isEmpty
            ? const <Delivery>[]
            : await broker._reserveBroadcast(
                broadcastChannels,
                workerId,
                prefetch,
              );
        if (jobs.isEmpty && broadcasts.isEmpty) {
          await Future<void>.delayed(broker.pollInterval);
          continue;
        }
        final leaseExpiresAt = stemNow().toUtc().add(
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
      } on Object catch (error, stack) {
        final queueLabel = queue ?? '<broadcast-only>';
        stemLogger.warning(
          'Consumer loop error (queue=$queueLabel, worker=$workerId): '
          '$error\n$stack',
          fields: broker._logContext({
            'queue': queueLabel,
            'worker': workerId,
            'error': error.toString(),
            'stack': stack.toString(),
          }),
        );
        if (controller.isClosed) return;
        controller.addError(error, stack);
        await Future<void>.delayed(broker.pollInterval);
      }
    }
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
