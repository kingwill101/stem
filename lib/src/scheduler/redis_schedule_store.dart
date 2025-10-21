import 'dart:convert';
import 'dart:io';

import 'package:redis/redis.dart';

import '../core/contracts.dart';
import '../security/tls.dart';
import 'schedule_calculator.dart';

/// Redis-backed implementation of [ScheduleStore].
class RedisScheduleStore implements ScheduleStore {
  RedisScheduleStore._(
    this._connection,
    this._command, {
    this.namespace = 'stem',
    this.lockTtl = const Duration(seconds: 5),
    ScheduleCalculator? calculator,
  }) : _calculator = calculator ?? ScheduleCalculator();

  final RedisConnection _connection;
  final Command _command;
  final String namespace;
  final Duration lockTtl;
  final ScheduleCalculator _calculator;

  bool _closed = false;

  static Future<RedisScheduleStore> connect(
    String uri, {
    String namespace = 'stem',
    Duration lockTtl = const Duration(seconds: 5),
    ScheduleCalculator? calculator,
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
          component: 'redis schedule store',
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

    return RedisScheduleStore._(
      connection,
      command,
      namespace: namespace,
      lockTtl: lockTtl,
      calculator: calculator,
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _connection.close();
  }

  String get _indexKey => '$namespace:schedule:index';
  String _entryKey(String id) => '$namespace:schedule:$id';
  String _lockKey(String id) => '$namespace:schedule:$id:lock';

  Future<dynamic> _send(List<Object> command) => _command.send_object(command);

  Map<String, String> _listToMap(List<dynamic> data) {
    final map = <String, String>{};
    for (var i = 0; i < data.length; i += 2) {
      final key = data[i] as String;
      final value = data[i + 1] as String;
      map[key] = value;
    }
    return map;
  }

  ScheduleEntry _entryFromMap(String id, Map<String, String> data) {
    return ScheduleEntry(
      id: id,
      taskName: data['taskName'] ?? '',
      queue: data['queue'] ?? 'default',
      spec: data['spec'] ?? 'every:60s',
      args: data['args'] != null
          ? (jsonDecode(data['args']!) as Map).cast<String, Object?>()
          : const {},
      enabled: data['enabled'] != null ? data['enabled'] == 'true' : true,
      jitter: data['jitterMs'] != null && data['jitterMs']!.isNotEmpty
          ? Duration(milliseconds: int.parse(data['jitterMs']!))
          : null,
      lastRunAt: data['lastRunAt'] != null && data['lastRunAt']!.isNotEmpty
          ? DateTime.parse(data['lastRunAt']!)
          : null,
      nextRunAt: data['nextRunAt'] != null && data['nextRunAt']!.isNotEmpty
          ? DateTime.parse(data['nextRunAt']!)
          : null,
      lastJitter:
          data['lastJitterMs'] != null && data['lastJitterMs']!.isNotEmpty
              ? Duration(milliseconds: int.parse(data['lastJitterMs']!))
              : null,
      lastError:
          data['lastError']?.isNotEmpty == true ? data['lastError'] : null,
      timezone: data['timezone']?.isNotEmpty == true ? data['timezone'] : null,
      meta: data['meta'] != null
          ? (jsonDecode(data['meta']!) as Map).cast<String, Object?>()
          : const {},
    );
  }

  @override
  Future<List<ScheduleEntry>> due(DateTime now, {int limit = 100}) async {
    final idsRaw = await _send([
      'ZRANGEBYSCORE',
      _indexKey,
      '-inf',
      now.millisecondsSinceEpoch.toString(),
      'LIMIT',
      '0',
      limit.toString(),
    ]);

    if (idsRaw is! List || idsRaw.isEmpty) {
      return const [];
    }

    final entries = <ScheduleEntry>[];
    for (final id in idsRaw.cast<String>()) {
      if (entries.length >= limit) break;
      final lock = await _send([
        'SET',
        _lockKey(id),
        '1',
        'NX',
        'PX',
        lockTtl.inMilliseconds.toString(),
      ]);
      if (lock != 'OK') {
        continue;
      }
      final data = await _send(['HGETALL', _entryKey(id)]);
      if (data is! List || data.isEmpty) {
        await _send(['DEL', _lockKey(id)]);
        continue;
      }
      final entry = _entryFromMap(id, _listToMap(data));
      if (!entry.enabled) {
        await _send(['DEL', _lockKey(id)]);
        continue;
      }
      entries.add(entry);
    }
    return entries;
  }

  @override
  Future<void> upsert(ScheduleEntry entry) async {
    final now = DateTime.now();
    final nextRun = entry.nextRunAt ??
        _calculator.nextRun(
          entry,
          entry.lastRunAt ?? now,
          includeJitter: false,
        );

    final encodedArgs = jsonEncode(entry.args);
    final encodedMeta = jsonEncode(entry.meta);
    await _send([
      'HSET',
      _entryKey(entry.id),
      'taskName',
      entry.taskName,
      'queue',
      entry.queue,
      'spec',
      entry.spec,
      'args',
      encodedArgs,
      'enabled',
      entry.enabled.toString(),
      'jitterMs',
      entry.jitter?.inMilliseconds.toString() ?? '',
      'lastRunAt',
      entry.lastRunAt?.toIso8601String() ?? '',
      'nextRunAt',
      nextRun.toIso8601String(),
      'lastJitterMs',
      entry.lastJitter?.inMilliseconds.toString() ?? '',
      'lastError',
      entry.lastError ?? '',
      'timezone',
      entry.timezone ?? '',
      'meta',
      encodedMeta,
    ]);

    await _send([
      'ZADD',
      _indexKey,
      nextRun.millisecondsSinceEpoch.toString(),
      entry.id,
    ]);
    await _send(['DEL', _lockKey(entry.id)]);
  }

  @override
  Future<void> remove(String id) async {
    await _send(['DEL', _entryKey(id)]);
    await _send(['ZREM', _indexKey, id]);
    await _send(['DEL', _lockKey(id)]);
  }

  @override
  Future<List<ScheduleEntry>> list({int? limit}) async {
    final stop = limit != null ? (limit - 1).toString() : '-1';
    final idsRaw = await _send(['ZRANGE', _indexKey, '0', stop]);
    if (idsRaw is! List || idsRaw.isEmpty) return const [];
    final entries = <ScheduleEntry>[];
    for (final id in idsRaw.cast<String>()) {
      final data = await _send(['HGETALL', _entryKey(id)]);
      if (data is! List || data.isEmpty) continue;
      entries.add(_entryFromMap(id, _listToMap(data)));
    }
    return entries;
  }

  @override
  Future<ScheduleEntry?> get(String id) async {
    final data = await _send(['HGETALL', _entryKey(id)]);
    if (data is! List || data.isEmpty) return null;
    return _entryFromMap(id, _listToMap(data));
  }

  @override
  Future<void> markExecuted(
    String id, {
    required DateTime executedAt,
    Duration? jitter,
    String? lastError,
  }) async {
    final data = await _send(['HGETALL', _entryKey(id)]);
    if (data is! List || data.isEmpty) {
      await _send(['DEL', _lockKey(id)]);
      return;
    }
    final map = _listToMap(data);
    final entry = _entryFromMap(id, map);
    final next = _calculator.nextRun(
      entry.copyWith(lastRunAt: executedAt),
      executedAt,
      includeJitter: false,
    );
    await _send([
      'HSET',
      _entryKey(id),
      'lastRunAt',
      executedAt.toIso8601String(),
      'nextRunAt',
      next.toIso8601String(),
      'lastJitterMs',
      jitter?.inMilliseconds.toString() ?? '',
      'lastError',
      lastError ?? '',
    ]);
    await _send([
      'ZADD',
      _indexKey,
      next.millisecondsSinceEpoch.toString(),
      id,
    ]);
    await _send(['DEL', _lockKey(id)]);
  }
}
