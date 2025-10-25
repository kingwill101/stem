import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:redis/redis.dart';
import 'package:uuid/uuid.dart';

import '../config/config.dart';
import '../config/tls.dart';
import '../stem/control_messages.dart';
import 'models.dart';
import 'redis_handle.dart';

abstract class DashboardDataSource {
  Future<List<QueueSummary>> fetchQueueSummaries();
  Future<List<WorkerStatus>> fetchWorkerStatuses();
  Future<void> enqueueTask(EnqueueRequest request);
  Future<List<ControlReplyMessage>> sendControlCommand(
    ControlCommandMessage command, {
    Duration timeout,
  });
  Future<void> close();
}

abstract class _DashboardBackplane {
  Future<Set<String>> discoverQueues();
  Future<int> pendingCount(String queue);
  Future<int> inflightCount(String queue);
  Future<int> deadLetterCount(String queue);
  Future<List<WorkerStatus>> workerStatuses();
  Future<void> enqueue(EnqueueRequest request);
  Future<List<ControlReplyMessage>> sendControlCommand(
    ControlCommandMessage command, {
    Duration timeout,
  });
  Future<void> close();
}

class StemDashboardService implements DashboardDataSource {
  StemDashboardService._(this._backplane);

  final _DashboardBackplane _backplane;

  static Future<StemDashboardService> connect(DashboardConfig config) async {
    final uri = Uri.parse(config.brokerUrl);
    switch (uri.scheme) {
      case 'redis':
      case 'rediss':
        final broker = await _connectRedis(config.brokerUrl, config.tls);
        final backend = config.resultBackendUrl == config.brokerUrl
            ? broker
            : await _connectRedis(config.resultBackendUrl, config.tls);
        final backplane = _RedisDashboardBackplane(
          config,
          brokerHandle: broker,
          backendHandle: backend,
        );
        return StemDashboardService._(backplane);
      case 'memory':
        final backplane = _MemoryDashboardBackplane(
          namespace: config.namespace,
        );
        return StemDashboardService._(backplane);
      default:
        throw UnsupportedError(
          'Unsupported broker scheme "${uri.scheme}". '
          'Only redis, rediss, and memory are currently supported.',
        );
    }
  }

  @override
  Future<List<QueueSummary>> fetchQueueSummaries() async {
    final queues = await _backplane.discoverQueues();
    final summaries = <QueueSummary>[];
    for (final queue in queues) {
      final pending = await _backplane.pendingCount(queue);
      final inflight = await _backplane.inflightCount(queue);
      final dead = await _backplane.deadLetterCount(queue);
      summaries.add(
        QueueSummary(
          queue: queue,
          pending: pending,
          inflight: inflight,
          deadLetters: dead,
        ),
      );
    }
    summaries.sort((a, b) => a.queue.compareTo(b.queue));
    return summaries;
  }

  @override
  Future<List<WorkerStatus>> fetchWorkerStatuses() {
    return _backplane.workerStatuses();
  }

  @override
  Future<void> enqueueTask(EnqueueRequest request) {
    return _backplane.enqueue(request);
  }

  @override
  Future<List<ControlReplyMessage>> sendControlCommand(
    ControlCommandMessage command, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    return _backplane.sendControlCommand(command, timeout: timeout);
  }

  @override
  Future<void> close() => _backplane.close();
}

class _MemoryDashboardBackplane implements _DashboardBackplane {
  _MemoryDashboardBackplane({required this.namespace});

  final String namespace;
  final Map<String, List<EnqueueRequest>> _queues = {};
  final Map<String, WorkerStatus> _workers = {};

  @override
  Future<Set<String>> discoverQueues() async =>
      _queues.keys.toSet()..add('default');

  @override
  Future<int> pendingCount(String queue) async => _queues[queue]?.length ?? 0;

  @override
  Future<int> inflightCount(String queue) async => 0;

  @override
  Future<int> deadLetterCount(String queue) async => 0;

  @override
  Future<List<WorkerStatus>> workerStatuses() async =>
      _workers.values.toList(growable: false);

  @override
  Future<void> enqueue(EnqueueRequest request) async {
    final list = _queues.putIfAbsent(request.queue, () => <EnqueueRequest>[]);
    list.add(request);
  }

  @override
  Future<List<ControlReplyMessage>> sendControlCommand(
    ControlCommandMessage command, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    // Memory backplane has no workers to command yet.
    return const [];
  }

  @override
  Future<void> close() async {}
}

class _RedisDashboardBackplane implements _DashboardBackplane {
  _RedisDashboardBackplane(
    this._config, {
    required RedisHandle brokerHandle,
    required RedisHandle backendHandle,
  }) : _broker = brokerHandle,
       _backend = backendHandle;

  final DashboardConfig _config;
  final RedisHandle _broker;
  final RedisHandle _backend;
  static final Uuid _uuid = Uuid();

  @override
  Future<Set<String>> discoverQueues() async {
    final namespace = _config.namespace;
    final streamPrefix = '$namespace:stream:';
    final keys = await _scanKeys(_broker, '$streamPrefix*');
    final queues = <String>{};
    for (final key in keys) {
      final queue = _queueNameFromStreamKey(streamPrefix, key);
      if (queue != null) queues.add(queue);
    }
    if (queues.isEmpty) {
      queues.add('default');
    }
    return queues;
  }

  @override
  Future<int> pendingCount(String queue) async {
    final namespace = _config.namespace;
    final streamKeys = _streamVariants(namespace, queue);
    var pending = 0;
    for (final streamKey in streamKeys) {
      final length = await _safeSend(_broker, ['XLEN', streamKey]);
      pending += length;
    }
    final delayedKey = '$namespace:delayed:$queue';
    pending += await _safeSend(_broker, ['ZCARD', delayedKey]);
    return pending;
  }

  @override
  Future<int> inflightCount(String queue) async {
    final namespace = _config.namespace;
    final streamKeys = _streamVariants(namespace, queue);
    var inflight = 0;
    for (final streamKey in streamKeys) {
      final result = await _broker.send([
        'XPENDING',
        streamKey,
        _groupKey(namespace, queue),
      ]);
      inflight += _pendingCountFromXp(result);
    }
    return inflight;
  }

  @override
  Future<int> deadLetterCount(String queue) async {
    final key = '${_config.namespace}:dead:$queue';
    return _safeSend(_broker, ['LLEN', key]);
  }

  @override
  Future<List<WorkerStatus>> workerStatuses() async {
    final namespace = _config.namespace;
    final indexKey = '$namespace:worker:heartbeats';
    final raw = await _backend.send(['SMEMBERS', indexKey]);
    if (raw is! List) return const [];

    final statuses = <WorkerStatus>[];
    for (final id in raw.cast<String>()) {
      final key = '$namespace:worker:heartbeat:$id';
      final heartbeatRaw = await _backend.send(['GET', key]);
      if (heartbeatRaw is String) {
        try {
          final map = jsonDecode(heartbeatRaw) as Map<String, Object?>;
          statuses.add(WorkerStatus.fromJson(map));
        } catch (_) {
          // ignore malformed heartbeats
        }
      } else {
        await _backend.send(['SREM', indexKey, id]);
      }
    }

    statuses.sort((a, b) => a.workerId.compareTo(b.workerId));
    return statuses;
  }

  @override
  Future<void> enqueue(EnqueueRequest request) async {
    final streamKey = '${_config.namespace}:stream:${request.queue}';
    await _ensureGroup(streamKey, request.queue);
    final envelopeId = _uuid.v4();
    final now = DateTime.now().toUtc();
    await _broker.send([
      'XADD',
      streamKey,
      '*',
      ..._serializeEnvelope(envelopeId, request, now),
    ]);
  }

  @override
  Future<List<ControlReplyMessage>> sendControlCommand(
    ControlCommandMessage command, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final namespace = _config.namespace;
    final replyKey = ControlQueueNames.reply(namespace, command.requestId);
    await _broker.send(['DEL', replyKey]);

    final targetQueues = command.targets.isEmpty
        ? <String>[ControlQueueNames.broadcast(namespace)]
        : command.targets
              .map((target) => ControlQueueNames.worker(namespace, target))
              .toList();

    final now = DateTime.now().toUtc();
    for (final queue in targetQueues) {
      final fields = _serializeControlEnvelope(queue, command, now);
      await _broker.send(['XADD', queue, '*', ...fields]);
    }

    final expectedReplies = command.targets.isEmpty
        ? null
        : command.targets.length;

    final deadline = DateTime.now().add(timeout);
    final replies = <ControlReplyMessage>[];
    var lastId = '0-0';

    while (DateTime.now().isBefore(deadline)) {
      final remaining = deadline.difference(DateTime.now());
      final blockMs = remaining.inMilliseconds;
      if (blockMs <= 0) break;

      final response = await _broker.send([
        'XREAD',
        'BLOCK',
        blockMs.toString(),
        'STREAMS',
        replyKey,
        lastId,
      ]);

      final lastSeenId = _appendControlReplies(response, replies);
      if (lastSeenId != null) {
        lastId = lastSeenId;
      }

      if (expectedReplies != null && replies.length >= expectedReplies) {
        break;
      }
    }

    await _broker.send(['DEL', replyKey]);
    return replies;
  }

  @override
  Future<void> close() async {
    await Future.wait([
      _broker.close(),
      if (!identical(_broker, _backend)) _backend.close(),
    ]);
  }

  Future<List<String>> _scanKeys(RedisHandle handle, String pattern) async {
    var cursor = '0';
    final results = <String>[];
    do {
      final reply = await handle.send([
        'SCAN',
        cursor,
        'MATCH',
        pattern,
        'COUNT',
        '200',
      ]);
      if (reply is! List || reply.length != 2) {
        break;
      }
      cursor = reply[0] as String? ?? '0';
      final keys = reply[1];
      if (keys is List) {
        results.addAll(keys.cast<String>());
      }
    } while (cursor != '0');
    return results;
  }

  static List<String> _streamVariants(String namespace, String queue) {
    final base = '$namespace:stream:$queue';
    return [
      base,
      for (var priority = 1; priority <= 9; priority++) '$base:p$priority',
    ];
  }

  static String _groupKey(String namespace, String queue) =>
      '$namespace:group:$queue';

  String? _queueNameFromStreamKey(String prefix, String key) {
    if (!key.startsWith(prefix)) return null;
    var remainder = key.substring(prefix.length);
    final priorityMatch = RegExp(r':p\d+$');
    remainder = remainder.replaceAll(priorityMatch, '');
    if (remainder.isEmpty) return null;
    return remainder;
  }

  Future<void> _ensureGroup(String streamKey, String queue) async {
    final group = _groupKey(_config.namespace, queue);
    try {
      await _broker.send([
        'XGROUP',
        'CREATE',
        streamKey,
        group,
        '0',
        'MKSTREAM',
      ]);
    } catch (error) {
      final message = '$error'.toLowerCase();
      if (!message.contains('busygroup')) {
        rethrow;
      }
    }
  }

  List<Object> _serializeEnvelope(
    String id,
    EnqueueRequest request,
    DateTime now,
  ) {
    return [
      'id',
      id,
      'name',
      request.task,
      'args',
      jsonEncode(request.args),
      'headers',
      jsonEncode(const <String, String>{}),
      'enqueuedAt',
      now.toIso8601String(),
      'notBefore',
      '',
      'priority',
      request.priority.toString(),
      'attempt',
      '0',
      'maxRetries',
      request.maxRetries.toString(),
      'visibilityTimeout',
      '',
      'queue',
      request.queue,
      'meta',
      jsonEncode({'source': 'dashboard'}),
    ];
  }

  List<Object> _serializeControlEnvelope(
    String queue,
    ControlCommandMessage command,
    DateTime now,
  ) {
    return [
      'id',
      _uuid.v4(),
      'name',
      ControlEnvelopeTypes.command,
      'args',
      jsonEncode(command.toMap()),
      'headers',
      jsonEncode({'stem-control': '1'}),
      'enqueuedAt',
      now.toIso8601String(),
      'notBefore',
      '',
      'priority',
      '0',
      'attempt',
      '0',
      'maxRetries',
      '0',
      'visibilityTimeout',
      '',
      'queue',
      queue,
      'meta',
      jsonEncode({'source': 'dashboard'}),
    ];
  }

  String? _appendControlReplies(
    dynamic response,
    List<ControlReplyMessage> replies,
  ) {
    if (response is! List || response.isEmpty) {
      return null;
    }
    String? lastId;
    for (final streamEntry in response) {
      if (streamEntry is! List || streamEntry.length != 2) {
        continue;
      }
      final entries = streamEntry[1];
      if (entries is! List) continue;
      for (final entry in entries) {
        if (entry is! List || entry.length != 2) continue;
        final id = entry[0] as String;
        final fields = entry[1];
        if (fields is! List) continue;
        final map = <String, String>{};
        for (var i = 0; i < fields.length; i += 2) {
          map[fields[i] as String] = fields[i + 1] as String;
        }
        final argsJson = map['args'];
        if (argsJson == null) continue;
        try {
          final decoded = jsonDecode(argsJson) as Map<String, Object?>;
          replies.add(ControlReplyMessage.fromMap(decoded));
          lastId = id;
        } catch (_) {
          // ignore malformed replies
        }
      }
    }
    return lastId;
  }

  static Future<int> _safeSend(RedisHandle handle, List<Object> command) async {
    try {
      final result = await handle.send(command);
      return _asInt(result);
    } catch (_) {
      return 0;
    }
  }

  static int _pendingCountFromXp(dynamic value) {
    if (value is List && value.isNotEmpty) {
      return _asInt(value.first);
    }
    return 0;
  }

  static int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is List && value.isNotEmpty) {
      return _asInt(value.first);
    }
    return 0;
  }
}

Future<RedisHandle> _connectRedis(String uri, TlsConfig tls) async {
  final parsed = Uri.parse(uri);
  final host = parsed.host.isNotEmpty ? parsed.host : 'localhost';
  final port = parsed.hasPort ? parsed.port : 6379;
  final connection = RedisConnection();
  final scheme = parsed.scheme.isEmpty ? 'redis' : parsed.scheme;
  Command command;
  if (scheme == 'rediss') {
    final context = tls.toSecurityContext();
    try {
      final socket = await SecureSocket.connect(
        host,
        port,
        context: context,
        onBadCertificate: tls.allowInsecure ? (_) => true : null,
      );
      command = await connection.connectWithSocket(socket);
    } on HandshakeException catch (_) {
      stderr.writeln('[stem-dashboard] TLS handshake failed for $uri');
      rethrow;
    }
  } else {
    command = await connection.connect(host, port);
  }

  if (parsed.userInfo.isNotEmpty) {
    final parts = parsed.userInfo.split(':');
    final password = parts.length == 2 ? parts[1] : parts[0];
    if (password.isNotEmpty) {
      await command.send_object(['AUTH', password]);
    }
  }

  if (parsed.pathSegments.isNotEmpty) {
    final segment = parsed.pathSegments.firstWhere(
      (value) => value.isNotEmpty,
      orElse: () => '',
    );
    final db = int.tryParse(segment);
    if (db != null) {
      await command.send_object(['SELECT', db]);
    }
  }

  return RedisHandle(connection, command);
}
