import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:redis/redis.dart';

import '../core/contracts.dart';
import '../core/envelope.dart';
import '../security/tls.dart';

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

  int get activeClaimTimerCount => _claimTimers.length;

  bool _closed = false;

  static Future<RedisStreamsBroker> connect(
    String uri, {
    String namespace = 'stem',
    Duration blockTime = const Duration(seconds: 5),
    int delayedDrainBatch = 128,
    Duration defaultVisibilityTimeout = const Duration(seconds: 30),
    Duration claimInterval = const Duration(seconds: 30),
    TlsConfig? tls,
  }) async {
    final parsed = Uri.parse(uri);
    final host = parsed.host.isNotEmpty ? parsed.host : 'localhost';
    final port = parsed.hasPort ? parsed.port : 6379;
    final connection = RedisConnection();
    final scheme = parsed.scheme.isEmpty ? 'redis' : parsed.scheme;
    Command command;
    if (scheme == 'rediss') {
      final securityContext = tls?.toSecurityContext();
      try {
        final socket = await SecureSocket.connect(
          host,
          port,
          context: securityContext,
          onBadCertificate: tls?.allowInsecure == true ? (_) => true : null,
        );
        command = await connection.connectWithSocket(socket);
      } on HandshakeException catch (error, stack) {
        logTlsHandshakeFailure(
          component: 'redis broker',
          host: host,
          port: port,
          config: tls,
          error: error,
          stack: stack,
        );
        await connection.close();
        rethrow;
      }
    } else {
      command = await connection.connect(host, port);
    }

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

  /// Creates a broker instance using injected [connection] and [command].
  ///
  /// This is intended for unit tests that need to stub Redis behaviour without
  /// establishing a real network connection.
  static RedisStreamsBroker test({
    required RedisConnection connection,
    required Command command,
    String namespace = 'stem',
    Duration blockTime = const Duration(seconds: 5),
    int delayedDrainBatch = 128,
    Duration defaultVisibilityTimeout = const Duration(seconds: 30),
    Duration claimInterval = const Duration(seconds: 30),
  }) {
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
    for (final controller in List.of(_controllers)) {
      await controller.close();
    }
    _controllers.clear();
    for (final timer in _claimTimers.values) {
      timer.cancel();
    }
    Object? failure;
    StackTrace? failureStack;
    await runZonedGuarded(() => _connection.close(), (
      Object error,
      StackTrace stack,
    ) {
      if (_shouldSuppressClosedError(error)) {
        return;
      }
      failure = error;
      failureStack = stack;
    });
    if (failure != null) {
      Error.throwWithStackTrace(failure!, failureStack!);
    }
  }

  static const int _maxPriority = 9;

  String _streamKey(String queue) => '$namespace:stream:$queue';
  String _priorityStreamKey(String queue, int priority) {
    final normalized = _normalizedPriority(priority);
    if (normalized <= 0) return _streamKey(queue);
    return '${_streamKey(queue)}:p$normalized';
  }

  String _groupKey(String queue) => '$namespace:group:$queue';
  String _delayedKey(String queue) => '$namespace:delayed:$queue';
  String _deadKey(String queue) => '$namespace:dead:$queue';

  String _broadcastStreamKey(String channel) => '$namespace:broadcast:$channel';
  String _broadcastGroupKey(String channel, String consumer) =>
      '$namespace:broadcast:$channel:$consumer';

  List<String> _priorityStreamKeys(String queue) {
    return [
      for (var priority = _maxPriority; priority >= 0; priority--)
        _priorityStreamKey(queue, priority),
    ];
  }

  int _normalizedPriority(int value) {
    if (value <= 0) return 0;
    if (value >= _maxPriority) return _maxPriority;
    return value;
  }

  Future<dynamic> _send(List<Object> command) => _command.send_object(command);

  bool _shouldSuppressClosedError(Object error) {
    if (!_closed) return false;
    final message = '$error'.toLowerCase();
    return message.contains('streamsink is closed') ||
        message.contains('stream is closed') ||
        message.contains('connection closed') ||
        message.contains('socket is closed');
  }

  @override
  bool get supportsDelayed => true;

  @override
  bool get supportsPriority => true;

  Future<void> _ensureGroupForStream(String queue, String streamKey) async {
    final key = '$streamKey|${_groupKey(queue)}';
    if (_groupsCreated.contains(key)) return;
    try {
      await _send([
        'XGROUP',
        'CREATE',
        streamKey,
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

  Future<void> _ensureBroadcastGroup(String channel, String consumer) async {
    final stream = _broadcastStreamKey(channel);
    final group = _broadcastGroupKey(channel, consumer);
    final key = '$stream|$group';
    if (_groupsCreated.contains(key)) return;
    try {
      await _send(['XGROUP', 'CREATE', stream, group, '0', 'MKSTREAM']);
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
  Future<void> publish(Envelope envelope, {RoutingInfo? routing}) async {
    final resolvedRoute =
        routing ??
        RoutingInfo.queue(queue: envelope.queue, priority: envelope.priority);
    if (resolvedRoute.isBroadcast) {
      final channel = resolvedRoute.broadcastChannel ?? envelope.queue;
      final message = envelope.copyWith(queue: channel);
      await _publishBroadcast(
        channel,
        message,
        resolvedRoute.delivery ?? 'at-least-once',
      );
      return;
    }
    final target = resolvedRoute.queue ?? envelope.queue;
    final message = envelope.copyWith(
      queue: target,
      priority: resolvedRoute.priority ?? envelope.priority,
    );
    if (message.notBefore != null &&
        message.notBefore!.isAfter(DateTime.now())) {
      await _send([
        'ZADD',
        _delayedKey(target),
        message.notBefore!.millisecondsSinceEpoch.toString(),
        jsonEncode(message.toJson()),
      ]);
      return;
    }
    await _enqueue(target, message);
  }

  Future<void> _publishBroadcast(
    String channel,
    Envelope envelope,
    String delivery,
  ) async {
    await _send([
      'XADD',
      _broadcastStreamKey(channel),
      '*',
      ..._serializeEnvelope(envelope),
      'delivery',
      delivery,
    ]);
  }

  Future<void> _enqueue(String queue, Envelope envelope) async {
    final stream = _priorityStreamKey(queue, envelope.priority);
    await _ensureGroupForStream(queue, stream);
    await _send(['XADD', stream, '*', ..._serializeEnvelope(envelope)]);
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
    dynamic result;
    try {
      result = await _send([
        'ZRANGEBYSCORE',
        _delayedKey(queue),
        '-inf',
        nowMs.toString(),
        'LIMIT',
        '0',
        delayedDrainBatch.toString(),
      ]);
    } catch (error) {
      if (_shouldSuppressClosedError(error)) {
        return;
      }
      rethrow;
    }
    if (result is List && result.isNotEmpty) {
      for (final entry in result.cast<String>()) {
        dynamic removed;
        try {
          removed = await _send(['ZREM', _delayedKey(queue), entry]);
        } catch (error) {
          if (_shouldSuppressClosedError(error)) {
            return;
          }
          rethrow;
        }
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
    RoutingSubscription subscription, {
    int prefetch = 1,
    String? consumerGroup,
    String? consumerName,
  }) {
    if (subscription.queues.isEmpty) {
      throw ArgumentError(
        'RoutingSubscription must specify at least one queue.',
      );
    }
    if (subscription.queues.length > 1) {
      throw UnsupportedError(
        'RedisStreamsBroker currently supports consuming a single queue per subscription.',
      );
    }
    final queue = subscription.queues.first;
    final consumer =
        consumerName ?? 'consumer-${DateTime.now().microsecondsSinceEpoch}';
    final group = consumerGroup ?? _groupKey(queue);
    final streamKeys = _priorityStreamKeys(queue);
    final broadcastChannels = subscription.broadcastChannels;
    final claimTimerKeys = <String>{};

    late StreamController<Delivery> controller;
    controller = StreamController<Delivery>.broadcast(
      onCancel: () {
        _controllers.remove(controller);
        for (final key in claimTimerKeys) {
          _claimTimers.remove(key)?.cancel();
        }
        if (!controller.isClosed) {
          unawaited(controller.close());
        }
      },
    );
    _controllers.add(controller);

    Future<void> loop() async {
      while (!controller.isClosed && !_closed) {
        for (final stream in streamKeys) {
          await _ensureGroupForStream(queue, stream);
        }
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
            ...streamKeys,
            ...List.filled(streamKeys.length, '>'),
          ]);
        } catch (error) {
          if (_shouldSuppressClosedError(error)) {
            return;
          }
          if ('$error'.contains('NOGROUP')) {
            for (final stream in streamKeys) {
              _groupsCreated.remove('$stream|${_groupKey(queue)}');
              await _ensureGroupForStream(queue, stream);
            }
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
    for (final stream in streamKeys) {
      final key = _scheduleClaim(stream, group, consumer);
      claimTimerKeys.add(key);
    }

    for (final channel in broadcastChannels) {
      _listenBroadcast(channel, consumer, prefetch, controller);
      final key = _scheduleClaim(
        _broadcastStreamKey(channel),
        _broadcastGroupKey(channel, consumer),
        consumer,
      );
      claimTimerKeys.add(key);
    }
    return controller.stream;
  }

  void _listenBroadcast(
    String channel,
    String consumer,
    int prefetch,
    StreamController<Delivery> controller,
  ) {
    Future<void>(() async {
      final streamKey = _broadcastStreamKey(channel);
      final group = _broadcastGroupKey(channel, consumer);
      while (!controller.isClosed && !_closed) {
        await _ensureBroadcastGroup(channel, consumer);
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
            streamKey,
            '>',
          ]);
        } catch (error) {
          if (_shouldSuppressClosedError(error)) {
            return;
          }
          if ('$error'.contains('NOGROUP')) {
            _groupsCreated.remove('$streamKey|$group');
            await _ensureBroadcastGroup(channel, consumer);
            continue;
          }
          rethrow;
        }
        if (result == null) {
          continue;
        }
        final deliveries = _parseDeliveries(channel, group, consumer, result);
        for (final delivery in deliveries) {
          if (controller.isClosed) {
            break;
          }
          controller.add(delivery);
        }
      }
    });
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
      final streamKey = streamEntry[0] as String?;
      if (streamKey == null) continue;
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
        final receipt = '$streamKey|$group|$consumer|$id';
        final lease = envelope.visibilityTimeout ?? defaultVisibilityTimeout;
        final isBroadcast = streamKey.startsWith('$namespace:broadcast:');
        final route = isBroadcast
            ? RoutingInfo.broadcast(
                channel: envelope.queue,
                delivery: map['delivery'] ?? 'at-least-once',
              )
            : RoutingInfo.queue(
                queue: envelope.queue,
                priority: envelope.priority,
              );
        deliveries.add(
          Delivery(
            envelope: envelope,
            receipt: receipt,
            leaseExpiresAt: lease == Duration.zero
                ? null
                : DateTime.now().add(lease),
            route: route,
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

  String _claimTimerKey(String stream, String group, String consumer) =>
      '$stream|$group|$consumer';

  String _scheduleClaim(String stream, String group, String consumer) {
    final key = _claimTimerKey(stream, group, consumer);
    _claimTimers[key]?.cancel();
    _claimTimers[key] = Timer.periodic(claimInterval, (_) async {
      dynamic result;
      try {
        result = await _send([
          'XAUTOCLAIM',
          stream,
          group,
          consumer,
          claimInterval.inMilliseconds.toString(),
          '0-0',
          'COUNT',
          delayedDrainBatch.toString(),
          'JUSTID',
        ]);
      } catch (error) {
        if (_shouldSuppressClosedError(error)) {
          return;
        }
        rethrow;
      }
      if (result is List && result.length >= 2) {
        final ids = result[1];
        if (ids is List && ids.isNotEmpty) {
          for (final id in ids) {
            try {
              await _send([
                'XCLAIM',
                stream,
                group,
                consumer,
                '0',
                id,
                'JUSTID',
              ]);
            } catch (error) {
              if (_shouldSuppressClosedError(error)) {
                return;
              }
              rethrow;
            }
          }
        }
      }
    });
    return key;
  }

  @override
  Future<void> ack(Delivery delivery) async {
    final info = _parseReceipt(delivery.receipt);
    await _send(['XACK', info.stream, info.group, info.id]);
  }

  @override
  Future<void> nack(Delivery delivery, {bool requeue = true}) async {
    final info = _parseReceipt(delivery.receipt);
    if (delivery.route.isBroadcast) {
      await _send(['XACK', info.stream, info.group, info.id]);
      return;
    }
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

  @override
  Future<DeadLetterPage> listDeadLetters(
    String queue, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (limit <= 0) {
      return const DeadLetterPage(entries: []);
    }
    final start = offset < 0 ? 0 : offset;
    final stop = start + limit - 1;
    final result = await _send([
      'LRANGE',
      _deadKey(queue),
      start.toString(),
      stop.toString(),
    ]);
    if (result is! List) {
      return const DeadLetterPage(entries: []);
    }
    final entries = result
        .cast<String>()
        .map(_decodeDeadLetter)
        .whereType<DeadLetterEntry>()
        .toList();
    final nextOffset = entries.length == limit ? start + entries.length : null;
    return DeadLetterPage(entries: entries, nextOffset: nextOffset);
  }

  @override
  Future<DeadLetterEntry?> getDeadLetter(String queue, String id) async {
    final stored = await _fetchDeadLetters(queue);
    try {
      return stored.firstWhere((entry) => entry.entry.envelope.id == id).entry;
    } on StateError {
      return null;
    }
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
    final stored = await _fetchDeadLetters(queue);
    final candidates = stored.where((entry) {
      if (since == null) return true;
      return !entry.entry.deadAt.isBefore(since);
    }).toList()..sort((a, b) => a.entry.deadAt.compareTo(b.entry.deadAt));
    final selected = candidates.take(limit).toList();
    if (dryRun || selected.isEmpty) {
      return DeadLetterReplayResult(
        entries: selected.map((e) => e.entry).toList(),
        dryRun: true,
      );
    }
    final now = DateTime.now();
    for (final candidate in selected) {
      await _send(['LREM', _deadKey(queue), '1', candidate.raw]);
      final replayEnvelope = candidate.entry.envelope.copyWith(
        attempt: candidate.entry.envelope.attempt + 1,
        notBefore: delay != null ? now.add(delay) : null,
      );
      await _enqueue(queue, replayEnvelope.copyWith(queue: queue));
    }
    return DeadLetterReplayResult(
      entries: selected.map((e) => e.entry).toList(),
      dryRun: false,
    );
  }

  @override
  Future<int> purgeDeadLetters(
    String queue, {
    DateTime? since,
    int? limit,
  }) async {
    if (since == null && (limit == null || limit < 0)) {
      final length = await _send(['LLEN', _deadKey(queue)]);
      await _send(['DEL', _deadKey(queue)]);
      return _asInt(length);
    }

    final stored = await _fetchDeadLetters(queue);
    final candidates = stored.where((entry) {
      if (since == null) return true;
      return !entry.entry.deadAt.isBefore(since);
    }).toList()..sort((a, b) => b.entry.deadAt.compareTo(a.entry.deadAt));
    final selected = limit != null && limit >= 0
        ? candidates.take(limit).toList()
        : candidates;
    for (final candidate in selected) {
      await _send(['LREM', _deadKey(queue), '1', candidate.raw]);
    }
    return selected.length;
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
    final streams = _priorityStreamKeys(queue).toSet();
    for (final stream in streams) {
      await _send(['DEL', stream]);
      try {
        await _send(['XGROUP', 'DESTROY', stream, _groupKey(queue)]);
      } catch (_) {
        // Group may not exist; ignore.
      }
      _groupsCreated.remove('$stream|${_groupKey(queue)}');
    }
    await _send(['DEL', _delayedKey(queue)]);
    await _send(['DEL', _deadKey(queue)]);
  }

  @override
  Future<int?> pendingCount(String queue) async {
    var total = 0;
    for (final stream in _priorityStreamKeys(queue)) {
      final length = await _send(['XLEN', stream]);
      total += _asInt(length);
    }
    final delayed = await _send(['ZCARD', _delayedKey(queue)]);
    total += _asInt(delayed);
    return total;
  }

  @override
  Future<int?> inflightCount(String queue) async {
    var total = 0;
    for (final stream in _priorityStreamKeys(queue)) {
      final result = await _send(['XPENDING', stream, _groupKey(queue)]);
      if (result is List && result.isNotEmpty) {
        total += _asInt(result.first);
      }
    }
    return total;
  }

  DeadLetterEntry? _decodeDeadLetter(String raw) {
    try {
      final obj = jsonDecode(raw) as Map<String, Object?>;
      return DeadLetterEntry(
        envelope: Envelope.fromJson(
          (obj['envelope'] as Map).cast<String, Object?>(),
        ),
        reason: obj['reason'] as String?,
        meta: (obj['meta'] as Map?)?.cast<String, Object?>(),
        deadAt: DateTime.parse(obj['deadAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<_StoredDeadLetter>> _fetchDeadLetters(String queue) async {
    final result = await _send(['LRANGE', _deadKey(queue), '0', '-1']);
    if (result is! List) return const <_StoredDeadLetter>[];
    final entries = <_StoredDeadLetter>[];
    for (final raw in result.cast<String>()) {
      final decoded = _decodeDeadLetter(raw);
      if (decoded != null) {
        entries.add(_StoredDeadLetter(raw, decoded));
      }
    }
    return entries;
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

class _StoredDeadLetter {
  _StoredDeadLetter(this.raw, this.entry);

  final String raw;
  final DeadLetterEntry entry;
}
