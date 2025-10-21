import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:postgres/postgres.dart';

import '../core/contracts.dart';
import '../core/envelope.dart';
import '../postgres/postgres_client.dart';
import '../postgres/postgres_migrations.dart';

class PostgresBroker implements Broker {
  PostgresBroker._(
    this._client, {
    required this.defaultVisibilityTimeout,
    required this.pollInterval,
  });

  static Future<PostgresBroker> connect(
    String connectionString, {
    Duration defaultVisibilityTimeout = const Duration(seconds: 30),
    Duration pollInterval = const Duration(milliseconds: 500),
    String? applicationName,
  }) async {
    final client = PostgresClient(
      connectionString,
      applicationName: applicationName,
    );
    final broker = PostgresBroker._(
      client,
      defaultVisibilityTimeout: defaultVisibilityTimeout,
      pollInterval: pollInterval,
    );
    final migrations = PostgresMigrations(client);
    await migrations.ensureQueueTables();
    return broker;
  }

  final PostgresClient _client;
  final Duration defaultVisibilityTimeout;
  final Duration pollInterval;

  final Set<_ConsumerRunner> _consumers = {};
  final Random _random = Random();

  bool _closed = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final runner in List<_ConsumerRunner>.of(_consumers)) {
      runner.stop();
      await runner.controller.close();
    }
    _consumers.clear();
    await _client.close();
  }

  @override
  bool get supportsDelayed => true;

  @override
  bool get supportsPriority => false;

  @override
  Future<void> publish(Envelope envelope, {String? queue}) async {
    final targetQueue = (queue ?? envelope.queue).trim();
    final stored = envelope.copyWith(queue: targetQueue);
    await _client.run((PostgreSQLConnection conn) async {
      await conn.execute(
        '''
INSERT INTO stem_jobs (
  id,
  queue,
  envelope,
  attempt,
  max_retries,
  not_before,
  locked_until,
  locked_by,
  created_at
) VALUES (
  @id,
  @queue,
  @envelope::jsonb,
  @attempt,
  @maxRetries,
  @notBefore,
  NULL,
  NULL,
  @createdAt
)
ON CONFLICT (id) DO UPDATE SET
  queue = EXCLUDED.queue,
  envelope = EXCLUDED.envelope,
  attempt = EXCLUDED.attempt,
  max_retries = EXCLUDED.max_retries,
  not_before = EXCLUDED.not_before,
  locked_until = NULL,
  locked_by = NULL,
  created_at = EXCLUDED.created_at
''',
        substitutionValues: {
          'id': stored.id,
          'queue': targetQueue,
          'envelope': jsonEncode(stored.toJson()),
          'attempt': stored.attempt,
          'maxRetries': stored.maxRetries,
          'notBefore': stored.notBefore?.toUtc(),
          'createdAt': stored.enqueuedAt.toUtc(),
        },
      );
    });
  }

  @override
  Stream<Delivery> consume(
    String queue, {
    int prefetch = 1,
    String? consumerGroup,
    String? consumerName,
  }) {
    final group = consumerGroup ?? 'default';
    final consumer =
        consumerName ??
        'consumer-${DateTime.now().microsecondsSinceEpoch}'
            '-${_random.nextInt(1 << 16)}';
    final locker = _encodeLocker(queue, group, consumer);

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
    final receipt = _Receipt.parse(delivery.receipt);
    await _client.run((PostgreSQLConnection conn) async {
      await conn.execute('''
DELETE FROM stem_jobs
WHERE id = @id AND queue = @queue AND locked_by = @lockedBy
''', substitutionValues: receipt.toMap());
    });
  }

  @override
  Future<void> nack(Delivery delivery, {bool requeue = true}) async {
    final receipt = _Receipt.parse(delivery.receipt);
    if (!requeue) {
      await ack(delivery);
      return;
    }
    final updatedEnvelope = delivery.envelope.copyWith(
      queue: receipt.queue,
      attempt: delivery.envelope.attempt + 1,
    );
    await _client.run((PostgreSQLConnection conn) async {
      await conn.execute(
        '''
UPDATE stem_jobs
SET
  envelope = @envelope::jsonb,
  attempt = @attempt,
  max_retries = @maxRetries,
  not_before = @notBefore,
  locked_until = NULL,
  locked_by = NULL
WHERE id = @id AND queue = @queue AND locked_by = @lockedBy
''',
        substitutionValues: {
          ...receipt.toMap(),
          'envelope': jsonEncode(updatedEnvelope.toJson()),
          'attempt': updatedEnvelope.attempt,
          'maxRetries': updatedEnvelope.maxRetries,
          'notBefore': updatedEnvelope.notBefore?.toUtc(),
        },
      );
    });
  }

  @override
  Future<void> deadLetter(
    Delivery delivery, {
    String? reason,
    Map<String, Object?>? meta,
  }) async {
    final receipt = _Receipt.parse(delivery.receipt);
    final entryReason = (reason == null || reason.trim().isEmpty)
        ? 'unknown'
        : reason.trim();
    final deadAt = DateTime.now().toUtc();
    await _client.run((PostgreSQLConnection conn) async {
      await conn.transaction((PostgreSQLExecutionContext tx) async {
        await tx.execute('''
DELETE FROM stem_jobs
WHERE id = @id AND queue = @queue AND locked_by = @lockedBy
''', substitutionValues: receipt.toMap());
        await tx.execute(
          '''
INSERT INTO stem_jobs_dead (
  id,
  queue,
  envelope,
  reason,
  meta,
  dead_lettered_at
) VALUES (
  @id,
  @queue,
  @envelope::jsonb,
  @reason,
  @meta::jsonb,
  @deadAt
)
ON CONFLICT (id) DO UPDATE SET
  queue = EXCLUDED.queue,
  envelope = EXCLUDED.envelope,
  reason = EXCLUDED.reason,
  meta = EXCLUDED.meta,
  dead_lettered_at = EXCLUDED.dead_lettered_at
''',
          substitutionValues: {
            'id': delivery.envelope.id,
            'queue': receipt.queue,
            'envelope': jsonEncode(delivery.envelope.toJson()),
            'reason': entryReason,
            'meta': meta == null ? null : jsonEncode(meta),
            'deadAt': deadAt,
          },
        );
      });
    });
  }

  @override
  Future<void> purge(String queue) async {
    await _client.run((PostgreSQLConnection conn) async {
      await conn.execute(
        'DELETE FROM stem_jobs WHERE queue = @queue',
        substitutionValues: {'queue': queue},
      );
    });
  }

  @override
  Future<void> extendLease(Delivery delivery, Duration by) async {
    if (by <= Duration.zero) return;
    final receipt = _Receipt.parse(delivery.receipt);
    final milliseconds = by.inMilliseconds;
    await _client.run((PostgreSQLConnection conn) async {
      await conn.execute(
        '''
UPDATE stem_jobs
SET locked_until = COALESCE(locked_until, NOW())
  + (@ms * INTERVAL '1 millisecond')
WHERE id = @id AND queue = @queue AND locked_by = @lockedBy
''',
        substitutionValues: {...receipt.toMap(), 'ms': milliseconds},
      );
    });
  }

  @override
  Future<int?> pendingCount(String queue) async {
    final result = await _client.run((PostgreSQLConnection conn) async {
      final rows = await conn.query(
        '''
SELECT COUNT(1)
FROM stem_jobs
WHERE queue = @queue
  AND (not_before IS NULL OR not_before <= NOW())
  AND (locked_by IS NULL OR locked_until <= NOW())
''',
        substitutionValues: {'queue': queue},
      );
      if (rows.isEmpty) return 0;
      return _asInt(rows.first.first);
    });
    return result;
  }

  @override
  Future<int?> inflightCount(String queue) async {
    final result = await _client.run((PostgreSQLConnection conn) async {
      final rows = await conn.query(
        '''
SELECT COUNT(1)
FROM stem_jobs
WHERE queue = @queue
  AND locked_by IS NOT NULL
  AND (locked_until IS NULL OR locked_until > NOW())
''',
        substitutionValues: {'queue': queue},
      );
      if (rows.isEmpty) return 0;
      return _asInt(rows.first.first);
    });
    return result;
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
    final rows = await _client.run((PostgreSQLConnection conn) async {
      return conn.query(
        '''
SELECT envelope, reason, meta, dead_lettered_at
FROM stem_jobs_dead
WHERE queue = @queue
ORDER BY dead_lettered_at DESC
LIMIT @limit OFFSET @offset
''',
        substitutionValues: {
          'queue': queue,
          'limit': limit,
          'offset': normalizedOffset,
        },
      );
    });
    final entries = rows.map((row) {
      final envelope = _decodeEnvelope(row[0]);
      final reason = row[1] as String?;
      final meta = _decodeMeta(row[2]);
      final deadAt = (row[3] as DateTime).toUtc();
      return DeadLetterEntry(
        envelope: envelope,
        reason: reason,
        meta: meta,
        deadAt: deadAt,
      );
    }).toList();
    final nextOffset = entries.length == limit
        ? normalizedOffset + entries.length
        : null;
    return DeadLetterPage(entries: entries, nextOffset: nextOffset);
  }

  @override
  Future<DeadLetterEntry?> getDeadLetter(String queue, String id) async {
    final rows = await _client.run((PostgreSQLConnection conn) async {
      return conn.query(
        '''
SELECT envelope, reason, meta, dead_lettered_at
FROM stem_jobs_dead
WHERE queue = @queue AND id = @id
LIMIT 1
''',
        substitutionValues: {'queue': queue, 'id': id},
      );
    });
    if (rows.isEmpty) return null;
    final row = rows.first;
    return DeadLetterEntry(
      envelope: _decodeEnvelope(row[0]),
      reason: row[1] as String?,
      meta: _decodeMeta(row[2]),
      deadAt: (row[3] as DateTime).toUtc(),
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
    if (limit <= 0) {
      return DeadLetterReplayResult(entries: const [], dryRun: dryRun);
    }
    final result = await _client.run((PostgreSQLConnection conn) async {
      final dynamic replay = await conn.transaction((
        PostgreSQLExecutionContext tx,
      ) async {
        final rows = await tx.query(
          '''
SELECT id, envelope, reason, meta, dead_lettered_at
FROM stem_jobs_dead
WHERE queue = @queue
  AND (@since::timestamptz IS NULL OR dead_lettered_at >= @since)
ORDER BY dead_lettered_at ASC
FOR UPDATE SKIP LOCKED
LIMIT @limit
''',
          substitutionValues: {
            'queue': queue,
            'limit': limit,
            'since': since?.toUtc(),
          },
        );
        if (rows.isEmpty) {
          return DeadLetterReplayResult(entries: const [], dryRun: dryRun);
        }
        final entries = rows.map((row) {
          return DeadLetterEntry(
            envelope: _decodeEnvelope(row[1]),
            reason: row[2] as String?,
            meta: _decodeMeta(row[3]),
            deadAt: (row[4] as DateTime).toUtc(),
          );
        }).toList();
        if (dryRun) {
          return DeadLetterReplayResult(entries: entries, dryRun: true);
        }
        final now = DateTime.now().toUtc();
        for (var index = 0; index < rows.length; index++) {
          final row = rows[index];
          final id = row[0] as String;
          final entry = entries[index];
          final replayEnvelope = entry.envelope.copyWith(
            queue: queue,
            attempt: entry.envelope.attempt + 1,
            notBefore: delay == null ? null : now.add(delay),
          );
          await tx.execute(
            '''
INSERT INTO stem_jobs (
  id,
  queue,
  envelope,
  attempt,
  max_retries,
  not_before,
  locked_until,
  locked_by,
  created_at
) VALUES (
  @id,
  @queue,
  @envelope::jsonb,
  @attempt,
  @maxRetries,
  @notBefore,
  NULL,
  NULL,
  @createdAt
)
ON CONFLICT (id) DO UPDATE SET
  queue = EXCLUDED.queue,
  envelope = EXCLUDED.envelope,
  attempt = EXCLUDED.attempt,
  max_retries = EXCLUDED.max_retries,
  not_before = EXCLUDED.not_before,
  locked_until = NULL,
  locked_by = NULL,
  created_at = EXCLUDED.created_at
''',
            substitutionValues: {
              'id': id,
              'queue': queue,
              'envelope': jsonEncode(replayEnvelope.toJson()),
              'attempt': replayEnvelope.attempt,
              'maxRetries': replayEnvelope.maxRetries,
              'notBefore': replayEnvelope.notBefore?.toUtc(),
              'createdAt': replayEnvelope.enqueuedAt.toUtc(),
            },
          );
          await tx.execute(
            '''
DELETE FROM stem_jobs_dead
WHERE id = @id AND queue = @queue
''',
            substitutionValues: {'id': id, 'queue': queue},
          );
        }
        return DeadLetterReplayResult(entries: entries, dryRun: false);
      });
      return replay as DeadLetterReplayResult;
    });
    return result;
  }

  @override
  Future<int> purgeDeadLetters(
    String queue, {
    DateTime? since,
    int? limit,
  }) async {
    final effectiveLimit = limit != null && limit >= 0 ? limit : null;
    final result = await _client.run((PostgreSQLConnection conn) async {
      final dynamic deletedCount = await conn.transaction((
        PostgreSQLExecutionContext tx,
      ) async {
        final query = StringBuffer()
          ..writeln('''
SELECT id
FROM stem_jobs_dead
WHERE queue = @queue
  AND (@since::timestamptz IS NULL OR dead_lettered_at >= @since)
ORDER BY dead_lettered_at DESC
''');
        if (effectiveLimit != null) {
          query.writeln('LIMIT @limit');
        }
        final params = <String, Object?>{
          'queue': queue,
          'since': since?.toUtc(),
        };
        if (effectiveLimit != null) {
          params['limit'] = effectiveLimit;
        }
        final ids = await tx.query(
          query.toString(),
          substitutionValues: params,
        );
        if (ids.isEmpty) return 0;
        final idList = ids.map((row) => row[0] as String).toList();
        final deleted = await tx.execute(
          '''
DELETE FROM stem_jobs_dead
WHERE queue = @queue AND id = ANY(@ids)
''',
          substitutionValues: {'queue': queue, 'ids': idList},
        );
        return deleted;
      });
      return deletedCount as int;
    });
    return result;
  }

  Future<List<Delivery>> _reserve(
    String queue,
    String locker,
    int limit,
  ) async {
    return _client.run((PostgreSQLConnection conn) async {
      final dynamic list = await conn.transaction((
        PostgreSQLExecutionContext tx,
      ) async {
        final rows = await tx.query(
          '''
SELECT id, envelope
FROM stem_jobs
WHERE queue = @queue
  AND (not_before IS NULL OR not_before <= NOW())
  AND (locked_by IS NULL OR locked_until <= NOW())
ORDER BY not_before NULLS FIRST, created_at
FOR UPDATE SKIP LOCKED
LIMIT @limit
''',
          substitutionValues: {'queue': queue, 'limit': limit},
        );
        if (rows.isEmpty) {
          return const <Delivery>[];
        }
        final now = DateTime.now().toUtc();
        final deliveries = <Delivery>[];
        for (final row in rows) {
          final id = row[0] as String;
          var envelope = _decodeEnvelope(row[1]);
          if (envelope.queue != queue) {
            envelope = envelope.copyWith(queue: queue);
          }
          final lease = envelope.visibilityTimeout ?? defaultVisibilityTimeout;
          final leaseExpiresAt = lease == Duration.zero ? null : now.add(lease);
          await tx.execute(
            '''
UPDATE stem_jobs
SET locked_by = @lockedBy, locked_until = @lockedUntil
WHERE id = @id
''',
            substitutionValues: {
              'lockedBy': locker,
              'lockedUntil': leaseExpiresAt,
              'id': id,
            },
          );
          final receipt = _Receipt(
            queue: queue,
            id: id,
            lockedBy: locker,
          ).encode();
          deliveries.add(
            Delivery(
              envelope: envelope,
              receipt: receipt,
              leaseExpiresAt: leaseExpiresAt,
            ),
          );
        }
        return deliveries;
      });
      return list as List<Delivery>;
    });
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
  });

  final PostgresBroker broker;
  final StreamController<Delivery> controller;
  final String queue;
  final String locker;
  final int prefetch;

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
        final deliveries = await broker._reserve(queue, locker, prefetch);
        if (deliveries.isEmpty) {
          await Future.delayed(broker.pollInterval);
          continue;
        }
        for (final delivery in deliveries) {
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

class _Receipt {
  _Receipt({required this.queue, required this.id, required this.lockedBy});

  final String queue;
  final String id;
  final String lockedBy;

  String encode() => jsonEncode(toMap());

  Map<String, Object?> toMap() => {
    'queue': queue,
    'id': id,
    'lockedBy': lockedBy,
  };

  static _Receipt parse(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return _Receipt(
      queue: decoded['queue'] as String,
      id: decoded['id'] as String,
      lockedBy: decoded['lockedBy'] as String,
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is BigInt) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  return 0;
}

Envelope _decodeEnvelope(dynamic raw) {
  if (raw is Map) {
    return Envelope.fromJson(raw.cast<String, Object?>());
  }
  if (raw is String) {
    final map = (jsonDecode(raw) as Map).cast<String, Object?>();
    return Envelope.fromJson(map);
  }
  throw StateError('Unsupported envelope payload: $raw');
}

Map<String, Object?> _decodeMeta(dynamic raw) {
  if (raw == null) return const {};
  if (raw is Map) {
    return raw.cast<String, Object?>();
  }
  if (raw is String) {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return decoded.cast<String, Object?>();
    }
  }
  return const {};
}
