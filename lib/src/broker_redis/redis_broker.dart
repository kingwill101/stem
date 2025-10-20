import 'dart:async';
import 'dart:convert';

import 'package:redis/redis.dart';

import '../core/contracts.dart';
import '../core/envelope.dart';

class RedisStreamsBroker implements Broker {
  RedisStreamsBroker._(
    this._connection,
    this._command, {
    this.namespace = 'stem',
    this.blockTime = const Duration(seconds: 5),
    this.delayedDrainBatch = 128,
    this.defaultVisibilityTimeout = const Duration(seconds: 30),
    this.claimInterval = const Duration(seconds: 30),
  });

  final String namespace;
  final Duration blockTime;
  final int delayedDrainBatch;
  final Duration defaultVisibilityTimeout;
  final Duration claimInterval;

  final RedisConnection _connection;
  final Command _command;

  final Map<String, Timer> _claimTimers = {};
  final Set<StreamController<Delivery>> _controllers = {};
  final Set<String> _groupsCreated = {};

  bool _closed = false;

  static Future<RedisStreamsBroker> connect(
    String uri, {
    String namespace = 'stem',
    Duration blockTime = const Duration(seconds: 5),
    int delayedDrainBatch = 128,
    Duration defaultVisibilityTimeout = const Duration(seconds: 30),
    Duration claimInterval = const Duration(seconds: 30),
  }) async {
    final parsed = Uri.parse(uri);
    final host = parsed.host.isNotEmpty ? parsed.host : 'localhost';
    final port = parsed.hasPort ? parsed.port : 6379;
    final connection = RedisConnection();
    final command = await connection.connect(host, port);

    if (parsed.userInfo.isNotEmpty) {
      final parts = parsed.userInfo.split(':');
      final password = parts.length == 2 ? parts[1] : parts[0];
      await command.send_object(['AUTH', password]);
    }

    if (parsed.pathSegments.isNotEmpty) {
      final db = int.tryParse(parsed.pathSegments.first);
      if (db != null) {
        await command.send_object(['SELECT', db]);
      }
    }

    return RedisStreamsBroker._(
      connection,
      command,
      namespace: namespace,
      blockTime: blockTime,
      delayedDrainBatch: delayedDrainBatch,
      defaultVisibilityTimeout: defaultVisibilityTimeout,
      claimInterval: claimInterval,
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final controller in _controllers) {
      await controller.close();
    }
    _controllers.clear();
    for (final timer in _claimTimers.values) {
      timer.cancel();
    }
    await _connection.close();
  }

  String _streamKey(String queue) => '$namespace:stream:$queue';
  String _groupKey(String queue) => '$namespace:group:$queue';
  String _delayedKey(String queue) => '$namespace:delayed:$queue';
  String _deadKey(String queue) => '$namespace:dead:$queue';

  Future<dynamic> _send(List<Object> command) => _command.send_object(command);

  @override
  bool get supportsDelayed => true;

  @override
  bool get supportsPriority => false;

  Future<void> _ensureGroup(String queue) async {
    final key = '${_streamKey(queue)}|${_groupKey(queue)}';
    if (_groupsCreated.contains(key)) return;
    try {
      await _send([
        'XGROUP',
        'CREATE',
        _streamKey(queue),
        _groupKey(queue),
        '0', // use special ID to avoid delivering old entries
        'MKSTREAM',
      ]);
    } catch (e) {
      if ('$e'.contains('BUSYGROUP')) {
        // already created
      } else {
        rethrow;
      }
    }
    _groupsCreated.add(key);
  }

  @override
  Future<void> publish(Envelope envelope, {String? queue}) async {
    final target = queue ?? envelope.queue;
    if (envelope.notBefore != null &&
        envelope.notBefore!.isAfter(DateTime.now())) {
      await _send([
        'ZADD',
        _delayedKey(target),
        envelope.notBefore!.millisecondsSinceEpoch.toString(),
        jsonEncode(envelope.toJson()),
      ]);
      return;
    }
    await _enqueue(target, envelope);
  }

  Future<void> _enqueue(String queue, Envelope envelope) async {
    await _ensureGroup(queue);
    await _send([
      'XADD',
      _streamKey(queue),
      '*',
      ..._serializeEnvelope(envelope),
    ]);
  }

  List<String> _serializeEnvelope(Envelope envelope) {
    return [
      'id',
      envelope.id,
      'name',
      envelope.name,
      'args',
      jsonEncode(envelope.args),
      'headers',
      jsonEncode(envelope.headers),
      'enqueuedAt',
      envelope.enqueuedAt.toIso8601String(),
      'notBefore',
      envelope.notBefore?.toIso8601String() ?? '',
      'priority',
      envelope.priority.toString(),
      'attempt',
      envelope.attempt.toString(),
      'maxRetries',
      envelope.maxRetries.toString(),
      'visibilityTimeout',
      envelope.visibilityTimeout?.inMilliseconds.toString() ?? '',
      'queue',
      envelope.queue,
      'meta',
      jsonEncode(envelope.meta),
    ];
  }

  Future<void> _drainDelayed(String queue) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final result = await _send([
      'ZRANGEBYSCORE',
      _delayedKey(queue),
      '-inf',
      nowMs.toString(),
      'LIMIT',
      '0',
      delayedDrainBatch.toString(),
    ]);
    if (result is List && result.isNotEmpty) {
      for (final entry in result.cast<String>()) {
        final removed = await _send(['ZREM', _delayedKey(queue), entry]);
        if (_asInt(removed) > 0) {
          final map = jsonDecode(entry) as Map<String, Object?>;
          final env = Envelope.fromJson(map).copyWith(notBefore: null);
          await _enqueue(queue, env);
        }
      }
    }
  }

  @override
  Stream<Delivery> consume(
    String queue, {
    int prefetch = 1,
    String? consumerGroup,
    String? consumerName,
  }) {
    final consumer =
        consumerName ?? 'consumer-${DateTime.now().microsecondsSinceEpoch}';
    final group = consumerGroup ?? _groupKey(queue);

    late StreamController<Delivery> controller;
    controller = StreamController<Delivery>.broadcast(
      onCancel: () {
        _controllers.remove(controller);
        if (!controller.isClosed) {
          unawaited(controller.close());
        }
      },
    );
    _controllers.add(controller);

    Future<void> loop() async {
      while (!controller.isClosed && !_closed) {
        await _ensureGroup(queue);
        await _drainDelayed(queue);
        dynamic result;
        try {
          result = await _send([
            'XREADGROUP',
            'GROUP',
            group,
            consumer,
            'BLOCK',
            blockTime.inMilliseconds.toString(),
            'COUNT',
            prefetch.toString(),
            'STREAMS',
            _streamKey(queue),
            '>',
          ]);
        } catch (error) {
          if ('$error'.contains('NOGROUP')) {
            final defaultKey = '${_streamKey(queue)}|${_groupKey(queue)}';
            _groupsCreated.remove(defaultKey);
            _groupsCreated.remove('${_streamKey(queue)}|$group');
            await _ensureGroup(queue);
            continue;
          }
          rethrow;
        }
        if (result == null) {
          continue;
        }
        final deliveries = _parseDeliveries(queue, group, consumer, result);
        for (final delivery in deliveries) {
          if (controller.isClosed) {
            break;
          }
          controller.add(delivery);
        }
      }
    }

    loop();
    _scheduleClaim(queue, group, consumer);
    return controller.stream;
  }

  List<Delivery> _parseDeliveries(
    String queue,
    String group,
    String consumer,
    dynamic raw,
  ) {
    final deliveries = <Delivery>[];
    if (raw is! List || raw.isEmpty) return deliveries;
    for (final streamEntry in raw) {
      if (streamEntry is! List || streamEntry.length != 2) continue;
      final entries = streamEntry[1];
      if (entries is! List) continue;
      for (final entry in entries) {
        if (entry is! List || entry.length != 2) continue;
        final id = entry[0] as String;
        final fields = entry[1];
        if (fields is! List) continue;
        final map = <String, String>{};
        for (var i = 0; i < fields.length; i += 2) {
          final field = fields[i] as String;
          final value = fields[i + 1] as String;
          map[field] = value;
        }
        final envelope = _envelopeFromMap(map);
        final receipt = '${_streamKey(queue)}|$group|$consumer|$id';
        final lease = envelope.visibilityTimeout ?? defaultVisibilityTimeout;
        deliveries.add(
          Delivery(
            envelope: envelope,
            receipt: receipt,
            leaseExpiresAt: lease == Duration.zero
                ? null
                : DateTime.now().add(lease),
          ),
        );
      }
    }
    return deliveries;
  }

  Envelope _envelopeFromMap(Map<String, String> map) {
    return Envelope(
      id: map['id'],
      name: map['name']!,
      args: jsonDecode(map['args'] ?? '{}') as Map<String, Object?>,
      headers: (jsonDecode(map['headers'] ?? '{}') as Map)
          .cast<String, String>(),
      enqueuedAt: DateTime.parse(
        map['enqueuedAt'] ?? DateTime.now().toIso8601String(),
      ),
      notBefore: (map['notBefore']?.isEmpty ?? true)
          ? null
          : DateTime.parse(map['notBefore']!),
      priority: int.tryParse(map['priority'] ?? '0') ?? 0,
      attempt: int.tryParse(map['attempt'] ?? '0') ?? 0,
      maxRetries: int.tryParse(map['maxRetries'] ?? '0') ?? 0,
      visibilityTimeout: (map['visibilityTimeout']?.isEmpty ?? true)
          ? null
          : Duration(milliseconds: int.parse(map['visibilityTimeout']!)),
      queue: map['queue'] ?? 'default',
      meta: jsonDecode(map['meta'] ?? '{}') as Map<String, Object?>,
    );
  }

  void _scheduleClaim(String queue, String group, String consumer) {
    _claimTimers['$queue|$consumer']?.cancel();
    _claimTimers['$queue|$consumer'] = Timer.periodic(claimInterval, (_) async {
      await _ensureGroup(queue);
      final result = await _send([
        'XAUTOCLAIM',
        _streamKey(queue),
        group,
        consumer,
        claimInterval.inMilliseconds.toString(),
        '0-0',
        'COUNT',
        delayedDrainBatch.toString(),
        'JUSTID',
      ]);
      if (result is List && result.length >= 2) {
        final ids = result[1];
        if (ids is List && ids.isNotEmpty) {
          // Requeue claimed ids with the same consumer for immediate delivery
          for (final id in ids) {
            await _send([
              'XCLAIM',
              _streamKey(queue),
              group,
              consumer,
              '0',
              id,
              'JUSTID',
            ]);
          }
        }
      }
    });
  }

  @override
  Future<void> ack(Delivery delivery) async {
    final info = _parseReceipt(delivery.receipt);
    await _send(['XACK', info.stream, info.group, info.id]);
  }

  @override
  Future<void> nack(Delivery delivery, {bool requeue = true}) async {
    final info = _parseReceipt(delivery.receipt);
    await _send(['XACK', info.stream, info.group, info.id]);
    if (requeue) {
      await _enqueue(
        delivery.envelope.queue,
        delivery.envelope.copyWith(attempt: delivery.envelope.attempt + 1),
      );
    }
  }

  @override
  Future<void> deadLetter(
    Delivery delivery, {
    String? reason,
    Map<String, Object?>? meta,
  }) async {
    final info = _parseReceipt(delivery.receipt);
    await _send(['XACK', info.stream, info.group, info.id]);
    await _send([
      'LPUSH',
      _deadKey(delivery.envelope.queue),
      jsonEncode({
        'envelope': delivery.envelope.toJson(),
        'reason': reason,
        'meta': meta,
        'deadAt': DateTime.now().toIso8601String(),
      }),
    ]);
  }

  Future<List<DeadLetterEntry>> deadLetters(String queue) async {
    final result = await _send(['LRANGE', _deadKey(queue), '0', '-1']);
    if (result is! List) return const [];
    return result.map((entry) {
      final obj = jsonDecode(entry as String) as Map<String, Object?>;
      return DeadLetterEntry(
        envelope: Envelope.fromJson(obj['envelope'] as Map<String, Object?>),
        reason: obj['reason'] as String?,
        meta: (obj['meta'] as Map?)?.cast<String, Object?>(),
        deadAt: DateTime.parse(obj['deadAt'] as String),
      );
    }).toList();
  }

  @override
  Future<void> extendLease(Delivery delivery, Duration by) async {
    final info = _parseReceipt(delivery.receipt);
    await _send([
      'XCLAIM',
      info.stream,
      info.group,
      info.consumer,
      '0',
      info.id,
      'JUSTID',
    ]);
  }

  @override
  Future<void> purge(String queue) async {
    await _send(['DEL', _streamKey(queue)]);
    await _send(['DEL', _delayedKey(queue)]);
    await _send(['DEL', _deadKey(queue)]);
    try {
      await _send(['XGROUP', 'DESTROY', _streamKey(queue), _groupKey(queue)]);
    } catch (_) {
      // Group may not exist; ignore.
    }
    _groupsCreated.remove('${_streamKey(queue)}|${_groupKey(queue)}');
  }

  @override
  Future<int?> pendingCount(String queue) async {
    final length = await _send(['XLEN', _streamKey(queue)]);
    final delayed = await _send(['ZCARD', _delayedKey(queue)]);
    return _asInt(length) + _asInt(delayed);
  }

  @override
  Future<int?> inflightCount(String queue) async {
    final result = await _send([
      'XPENDING',
      _streamKey(queue),
      _groupKey(queue),
    ]);
    if (result is List && result.isNotEmpty) {
      return _asInt(result.first);
    }
    return 0;
  }

  ReceiptInfo _parseReceipt(String receipt) {
    final parts = receipt.split('|');
    if (parts.length != 4) {
      throw StateError('Invalid receipt format: $receipt');
    }
    return ReceiptInfo(
      stream: parts[0],
      group: parts[1],
      consumer: parts[2],
      id: parts[3],
    );
  }

  int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is List && value.isNotEmpty) {
      return _asInt(value.first);
    }
    return 0;
  }
}

class ReceiptInfo {
  ReceiptInfo({
    required this.stream,
    required this.group,
    required this.consumer,
    required this.id,
  });

  final String stream;
  final String group;
  final String consumer;
  final String id;
}

class DeadLetterEntry {
  DeadLetterEntry({
    required this.envelope,
    this.reason,
    Map<String, Object?>? meta,
    required this.deadAt,
  }) : meta = Map.unmodifiable(meta ?? const {});

  final Envelope envelope;
  final String? reason;
  final Map<String, Object?> meta;
  final DateTime deadAt;
}
