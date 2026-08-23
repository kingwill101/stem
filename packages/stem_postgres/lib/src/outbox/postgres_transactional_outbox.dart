import 'dart:async';
import 'dart:convert';

import 'package:ormed/ormed.dart';
import 'package:stem/stem.dart';
import 'package:stem_postgres/src/connection.dart';

/// Durable, PostgreSQL-backed publication outbox.
///
/// Application writes and calls to [PostgresOutboxBroker.publish] must happen
/// inside [transaction]. A relay later calls [dispatch] to publish committed
/// rows to the underlying broker. Relay delivery is at least once: a process
/// crash after broker publication and before marking a row dispatched can
/// cause another publication. PostgreSQL broker publication is idempotent by
/// envelope id, but task handlers must still be safe for duplicate delivery.
class PostgresTransactionalOutbox {
  PostgresTransactionalOutbox._(
    this._connections, {
    required this.namespace,
  });

  /// Opens an outbox on an existing initialized [DataSource].
  ///
  /// The caller remains responsible for disposing [dataSource].
  static Future<PostgresTransactionalOutbox> fromDataSource(
    DataSource dataSource, {
    String namespace = 'stem',
    bool runMigrations = true,
  }) async {
    final connections = await PostgresConnections.openWithDataSource(
      dataSource,
      runMigrations: runMigrations,
    );
    return PostgresTransactionalOutbox._(
      connections,
      namespace: _normalizeNamespace(namespace),
    );
  }

  /// Opens an outbox with its own PostgreSQL data source.
  static Future<PostgresTransactionalOutbox> connect(
    String connectionString, {
    String namespace = 'stem',
  }) async {
    final connections = await PostgresConnections.open(
      connectionString: connectionString,
    );
    return PostgresTransactionalOutbox._(
      connections,
      namespace: _normalizeNamespace(namespace),
    );
  }

  static final Object _transactionZoneKey = Object();

  final PostgresConnections _connections;

  /// Namespace used to scope outbox rows.
  final String namespace;

  /// Closes the outbox's owned data source.
  ///
  /// An outbox created with [fromDataSource] does not dispose the caller's
  /// data source.
  Future<void> close() => _connections.close();

  /// Makes a producer-only broker facade that records publications in the
  /// current [transaction] instead of sending them immediately.
  ///
  /// All non-publication broker operations delegate to [delegate]. Pass the
  /// underlying broker, rather than this facade, to [dispatch].
  PostgresOutboxBroker wrap(QueueBroker delegate) =>
      PostgresOutboxBroker(this, delegate);

  /// Returns the outbox transaction active in the current asynchronous
  /// context, or `null` when no outbox transaction is active.
  PostgresOutboxTransaction? get currentTransaction {
    final value = Zone.current[_transactionZoneKey];
    return value is PostgresOutboxTransaction ? value : null;
  }

  /// Executes [action] and atomically commits its application writes and
  /// outbox publications.
  Future<T> transaction<T>(
    Future<T> Function(PostgresOutboxTransaction transaction) action,
  ) {
    return _connections.runInTransaction((context) {
      final transaction = PostgresOutboxTransaction._(
        this,
        context,
        namespace: namespace,
      );
      return runZoned(
        () => action(transaction),
        zoneValues: {_transactionZoneKey: transaction},
      );
    });
  }

  /// Returns the number of rows not yet marked as dispatched.
  Future<int> pendingCount() {
    return _connections.runInTransaction((context) async {
      return _outboxTable(context).whereEquals('namespace', namespace).whereIn(
        'status',
        const ['pending', 'processing', 'failed'],
      ).count();
    });
  }

  /// Publishes committed outbox rows through [broker].
  ///
  /// Rows are claimed with `FOR UPDATE SKIP LOCKED`, leased, and retried after
  /// [retryDelay] when publication fails. A stale processing lease can be
  /// reclaimed by a later relay invocation.
  Future<int> dispatch({
    required QueueBroker broker,
    int limit = 100,
    Duration lease = const Duration(minutes: 1),
    Duration retryDelay = const Duration(seconds: 5),
    String? workerId,
  }) async {
    if (limit <= 0) return 0;
    if (lease <= Duration.zero) {
      throw ArgumentError.value(lease, 'lease', 'Lease must be positive.');
    }
    final resolvedWorkerId =
        workerId ?? 'stem-outbox-${DateTime.now().microsecondsSinceEpoch}';
    final claimed = await _claim(
      limit: limit,
      lease: lease,
      workerId: resolvedWorkerId,
    );
    var published = 0;
    for (final message in claimed) {
      try {
        await broker.publish(message.envelope, routing: message.routing);
        if (await _markDispatched(message.id, workerId: resolvedWorkerId)) {
          published++;
        }
      } on Object catch (error, stackTrace) {
        await _markFailed(
          message.id,
          workerId: resolvedWorkerId,
          error: '$error\n$stackTrace',
          retryDelay: retryDelay,
        );
      }
    }
    return published;
  }

  Future<List<_ClaimedOutboxMessage>> _claim({
    required int limit,
    required Duration lease,
    required String workerId,
  }) {
    return _connections.runInTransaction((context) async {
      final now = DateTime.now().toUtc();
      final lockedUntil = now.add(lease);
      final rows = await _outboxTable(context)
          .whereEquals('namespace', namespace)
          .whereIn('status', const ['pending', 'processing', 'failed'])
          .whereRaw('available_at <= ?', [now])
          .whereRaw('(locked_until IS NULL OR locked_until <= ?)', [now])
          .orderBy('created_at')
          .limit(limit)
          .lock('FOR UPDATE SKIP LOCKED')
          .get();
      final claimed = <_ClaimedOutboxMessage>[];
      for (final row in rows) {
        final id = row['id']! as String;
        final attempts = _asInt(row['attempts']) + 1;
        await _outboxTable(context).whereEquals('id', id).update({
          'status': 'processing',
          'attempts': attempts,
          'locked_at': now,
          'locked_until': lockedUntil,
          'locked_by': workerId,
          'updated_at': now,
        });
        claimed.add(
          _ClaimedOutboxMessage(
            id: id,
            envelope: Envelope.fromJson(_asMap(row['envelope'])),
            routing: row['routing'] == null
                ? null
                : RoutingInfo.fromJson(_asMap(row['routing'])),
          ),
        );
      }
      return claimed;
    });
  }

  Future<bool> _markDispatched(String id, {required String workerId}) {
    return _connections.runInTransaction((context) async {
      final now = DateTime.now().toUtc();
      final updated = await _outboxTable(context)
          .whereEquals('id', id)
          .whereEquals('namespace', namespace)
          .whereEquals('status', 'processing')
          .whereEquals('locked_by', workerId)
          .update({
            'status': 'dispatched',
            'dispatched_at': now,
            'locked_at': null,
            'locked_until': null,
            'locked_by': null,
            'updated_at': now,
          });
      return updated > 0;
    });
  }

  Future<bool> _markFailed(
    String id, {
    required String workerId,
    required String error,
    required Duration retryDelay,
  }) {
    return _connections.runInTransaction((context) async {
      final now = DateTime.now().toUtc();
      final message = error.length > 4000 ? error.substring(0, 4000) : error;
      final updated = await _outboxTable(context)
          .whereEquals('id', id)
          .whereEquals('namespace', namespace)
          .whereEquals('status', 'processing')
          .whereEquals('locked_by', workerId)
          .update({
            'status': 'failed',
            'available_at': now.add(retryDelay),
            'last_error': message,
            'locked_at': null,
            'locked_until': null,
            'locked_by': null,
            'updated_at': now,
          });
      return updated > 0;
    });
  }
}

/// Active transaction passed to [PostgresTransactionalOutbox.transaction].
class PostgresOutboxTransaction {
  PostgresOutboxTransaction._(
    this.outbox,
    this.context, {
    required this.namespace,
  });

  /// Outbox that owns this transaction.
  final PostgresTransactionalOutbox outbox;

  /// Query context for application writes in the same transaction.
  final QueryContext context;

  /// Namespace used for publications in this transaction.
  final String namespace;

  /// Adds an already-encoded task envelope to the transaction's outbox.
  Future<void> enqueueEnvelope(
    Envelope envelope, {
    RoutingInfo? routing,
  }) async {
    final availableAt = envelope.notBefore?.toUtc() ?? DateTime.now().toUtc();
    await _outboxTable(context).create({
      'id': envelope.id,
      'namespace': namespace,
      'envelope': envelope.toJson(),
      'routing': routing?.toJson(),
      'status': 'pending',
      'available_at': availableAt,
      'attempts': 0,
      'created_at': DateTime.now().toUtc(),
      'updated_at': DateTime.now().toUtc(),
    });
  }
}

/// Producer facade that diverts publication into a Postgres outbox.
class PostgresOutboxBroker extends Broker
    implements
        LeaseBroker,
        InspectableBroker,
        DeadLetterBroker,
        BrokerCapabilitiesProvider {
  /// Creates an outbox facade around [delegate].
  PostgresOutboxBroker(this.outbox, this.delegate);

  /// Outbox receiving publications.
  final PostgresTransactionalOutbox outbox;

  /// Broker used for all operations other than publication.
  final QueueBroker delegate;

  @override
  Future<void> publish(Envelope envelope, {RoutingInfo? routing}) async {
    final transaction = outbox.currentTransaction;
    if (transaction == null || !identical(transaction.outbox, outbox)) {
      throw StateError(
        'PostgresOutboxBroker.publish must run inside '
        'PostgresTransactionalOutbox.transaction.',
      );
    }
    await transaction.enqueueEnvelope(envelope, routing: routing);
  }

  @override
  Stream<Delivery> consume(
    RoutingSubscription subscription, {
    int prefetch = 1,
    String? consumerGroup,
    String? consumerName,
  }) => delegate.consume(
    subscription,
    prefetch: prefetch,
    consumerGroup: consumerGroup,
    consumerName: consumerName,
  );

  @override
  Future<void> ack(Delivery delivery) => delegate.ack(delivery);

  @override
  Future<void> nack(Delivery delivery, {bool requeue = true}) =>
      delegate.nack(delivery, requeue: requeue);

  @override
  Future<void> deadLetter(
    Delivery delivery, {
    String? reason,
    Map<String, Object?>? meta,
  }) => delegate.deadLetter(delivery, reason: reason, meta: meta);

  @override
  Future<void> purge(String queue) {
    final legacy = delegate;
    if (legacy is Broker) return legacy.purge(queue);
    throw UnsupportedError('Queue purging is not supported.');
  }

  @override
  Future<void> extendLease(Delivery delivery, Duration by) =>
      delegate.extendLease(delivery, by);

  @override
  Future<int?> pendingCount(String queue) => delegate.pendingCount(queue);

  @override
  Future<int?> inflightCount(String queue) => delegate.inflightCount(queue);

  @override
  bool get supportsDelayed => delegate.capabilities.supportsDelayedDelivery;

  @override
  bool get supportsPriority => delegate.capabilities.supportsPriorityOrdering;

  @override
  BrokerCapabilities get capabilities => delegate.capabilities;

  @override
  Future<DeadLetterPage> listDeadLetters(
    String queue, {
    int limit = 50,
    int offset = 0,
  }) => delegate.listDeadLetters(queue, limit: limit, offset: offset);

  @override
  Future<DeadLetterEntry?> getDeadLetter(String queue, String id) =>
      delegate.getDeadLetter(queue, id);

  @override
  Future<DeadLetterReplayResult> replayDeadLetters(
    String queue, {
    int limit = 50,
    DateTime? since,
    Duration? delay,
    bool dryRun = false,
  }) => delegate.replayDeadLetters(
    queue,
    limit: limit,
    since: since,
    delay: delay,
    dryRun: dryRun,
  );

  @override
  Future<int> purgeDeadLetters(String queue, {DateTime? since, int? limit}) =>
      delegate.purgeDeadLetters(queue, since: since, limit: limit);

  @override
  Future<void> close() => delegate.close();
}

class _ClaimedOutboxMessage {
  const _ClaimedOutboxMessage({
    required this.id,
    required this.envelope,
    required this.routing,
  });

  final String id;
  final Envelope envelope;
  final RoutingInfo? routing;
}

String _normalizeNamespace(String namespace) {
  final value = namespace.trim();
  return value.isEmpty ? 'stem' : value;
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  if (value is String) {
    final decoded = jsonDecode(value);
    if (decoded is Map) return decoded.cast<String, Object?>();
  }
  throw StateError('Expected a JSON object in the task outbox.');
}

int _asInt(Object? value) => value is num ? value.toInt() : 0;

Query<AdHocRow> _outboxTable(QueryContext context) => context.table(
  'stem_task_outbox',
  columns: const [
    AdHocColumn(name: 'id', isNullable: false, isPrimaryKey: true),
    AdHocColumn(name: 'namespace', isNullable: false),
    AdHocColumn(name: 'envelope', isNullable: false),
    AdHocColumn(name: 'routing'),
    AdHocColumn(name: 'status', isNullable: false),
    AdHocColumn(name: 'available_at', isNullable: false),
    AdHocColumn(name: 'attempts', isNullable: false),
    AdHocColumn(name: 'locked_at'),
    AdHocColumn(name: 'locked_until'),
    AdHocColumn(name: 'locked_by'),
    AdHocColumn(name: 'last_error'),
    AdHocColumn(name: 'dispatched_at'),
    AdHocColumn(name: 'created_at', isNullable: false),
    AdHocColumn(name: 'updated_at', isNullable: false),
  ],
);
