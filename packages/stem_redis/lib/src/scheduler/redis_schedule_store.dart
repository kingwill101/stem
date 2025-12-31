import 'dart:convert';
import 'dart:io';

import 'package:redis/redis.dart';

import 'package:stem/stem.dart';

/// Redis-backed implementation of [ScheduleStore].
class RedisScheduleStore implements ScheduleStore {
  /// Creates a schedule store backed by Redis.
  RedisScheduleStore._(
    this._connection,
    this._command, {
    this.namespace = 'stem',
    this.lockTtl = const Duration(seconds: 5),
    ScheduleCalculator? calculator,
  }) : _calculator = calculator ?? ScheduleCalculator();

  final RedisConnection _connection;
  final Command _command;

  /// Namespace used to scope schedule keys.
  final String namespace;

  /// TTL used for schedule locks.
  final Duration lockTtl;
  final ScheduleCalculator _calculator;

  bool _closed = false;

  /// Connects to Redis and returns a schedule store instance.
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
          onBadCertificate: tls?.allowInsecure ?? false ? (_) => true : null,
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

  /// Closes the schedule store and releases Redis resources.
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
    ScheduleSpec spec;
    final specRaw = data['spec'];
    if (specRaw != null) {
      Object? decoded;
      try {
        decoded = jsonDecode(specRaw);
      } on Object {
        decoded = specRaw;
      }
      spec = ScheduleSpec.fromPersisted(decoded);
    } else {
      spec = ScheduleSpec.fromPersisted('every:60s');
    }
    Map<String, Object?> decodeJson(String? raw) {
      if (raw == null || raw.isEmpty) return const {};
      return (jsonDecode(raw) as Map).cast<String, Object?>();
    }

    Duration? parseDuration(String? raw) => raw != null && raw.isNotEmpty
        ? Duration(milliseconds: int.parse(raw))
        : null;
    DateTime? parseDate(String? raw) =>
        raw != null && raw.isNotEmpty ? DateTime.parse(raw) : null;
    final version = data['version'];
    final parsedVersion = version != null ? int.tryParse(version) ?? 0 : 0;
    return ScheduleEntry(
      id: id,
      taskName: data['taskName'] ?? '',
      queue: data['queue'] ?? 'default',
      spec: spec,
      args: decodeJson(data['args']),
      kwargs: decodeJson(data['kwargs']),
      enabled: !(data['enabled'] != null) || data['enabled'] == 'true',
      jitter: parseDuration(data['jitterMs']),
      lastRunAt: parseDate(data['lastRunAt']),
      nextRunAt: parseDate(data['nextRunAt']),
      lastJitter: parseDuration(data['lastJitterMs']),
      lastError: data['lastError']?.isNotEmpty ?? false
          ? data['lastError']
          : null,
      timezone: data['timezone']?.isNotEmpty ?? false ? data['timezone'] : null,
      totalRunCount: data['totalRunCount'] != null
          ? int.tryParse(data['totalRunCount']!) ?? 0
          : 0,
      lastSuccessAt: parseDate(data['lastSuccessAt']),
      lastErrorAt: parseDate(data['lastErrorAt']),
      drift: parseDuration(data['driftMs']),
      expireAt: parseDate(data['expireAt']),
      meta: decodeJson(data['meta']),
      version: parsedVersion,
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
      if (entry.expireAt != null && !now.isBefore(entry.expireAt!)) {
        await _send(['DEL', _lockKey(id)]);
        continue;
      }
      entries.add(entry);
    }
    return entries;
  }

  @override
  Future<void> upsert(ScheduleEntry entry) async {
    final now = DateTime.now().toUtc();
    var nextRun = entry.nextRunAt;
    if (entry.enabled) {
      nextRun ??= _calculator.nextRun(
        entry,
        entry.lastRunAt ?? now,
        includeJitter: false,
      );
    } else {
      nextRun ??= entry.lastRunAt ?? now;
    }

    final encodedArgs = jsonEncode(entry.args);
    final encodedKwargs = jsonEncode(entry.kwargs);
    final encodedSpec = jsonEncode(entry.spec.toJson());
    final encodedMeta = jsonEncode(entry.meta);
    final key = _entryKey(entry.id);
    final lockKey = _lockKey(entry.id);
    await _send(['WATCH', key]);
    var watchActive = true;
    try {
      final versionRaw = await _send(['HGET', key, 'version']);
      final currentVersion = versionRaw == null
          ? 0
          : versionRaw is int
          ? versionRaw
          : int.tryParse(versionRaw.toString()) ?? 0;
      if (versionRaw != null && entry.version != currentVersion) {
        throw ScheduleConflictException(
          entry.id,
          expectedVersion: entry.version,
          actualVersion: currentVersion,
        );
      }
      final nextVersion = currentVersion + 1;

      await _send(['MULTI']);
      await _send([
        'HSET',
        key,
        'taskName',
        entry.taskName,
        'queue',
        entry.queue,
        'spec',
        encodedSpec,
        'args',
        encodedArgs,
        'kwargs',
        encodedKwargs,
        'enabled',
        if (entry.enabled) 'true' else 'false',
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
        'totalRunCount',
        entry.totalRunCount.toString(),
        'lastSuccessAt',
        entry.lastSuccessAt?.toIso8601String() ?? '',
        'lastErrorAt',
        entry.lastErrorAt?.toIso8601String() ?? '',
        'driftMs',
        entry.drift?.inMilliseconds.toString() ?? '',
        'expireAt',
        entry.expireAt?.toIso8601String() ?? '',
        'meta',
        encodedMeta,
        'version',
        nextVersion.toString(),
      ]);
      await _send([
        'ZADD',
        _indexKey,
        nextRun.millisecondsSinceEpoch.toString(),
        entry.id,
      ]);
      await _send(['DEL', lockKey]);
      final execResult = await _send(['EXEC']);
      watchActive = false;
      if (execResult == null) {
        throw ScheduleConflictException(
          entry.id,
          expectedVersion: entry.version,
          actualVersion: currentVersion,
        );
      }
    } finally {
      if (watchActive) {
        await _send(['UNWATCH']);
      }
    }
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
    required DateTime scheduledFor,
    required DateTime executedAt,
    Duration? jitter,
    String? lastError,
    bool success = true,
    Duration? runDuration,
    DateTime? nextRunAt,
    Duration? drift,
  }) async {
    final key = _entryKey(id);
    final lockKey = _lockKey(id);
    await _send(['WATCH', key]);
    var watchActive = true;
    var committed = false;
    try {
      final data = await _send(['HGETALL', key]);
      if (data is! List || data.isEmpty) {
        await _send(['UNWATCH']);
        watchActive = false;
        await _send(['DEL', lockKey]);
        return;
      }
      final map = _listToMap(data);
      final entry = _entryFromMap(id, map);
      final resolvedSuccess = success && lastError == null;
      final updated = entry.copyWith(
        lastRunAt: executedAt,
        lastError: lastError,
        lastJitter: jitter,
        lastSuccessAt: resolvedSuccess ? executedAt : entry.lastSuccessAt,
        lastErrorAt: resolvedSuccess ? entry.lastErrorAt : executedAt,
        totalRunCount: entry.totalRunCount + 1,
        drift: drift ?? entry.drift,
      );
      var next = nextRunAt;
      var enabled = updated.enabled;
      if (next == null && enabled) {
        try {
          next = _calculator.nextRun(updated, executedAt, includeJitter: false);
        } on Object {
          next = executedAt;
        }
      }
      if (updated.expireAt != null && !executedAt.isBefore(updated.expireAt!)) {
        enabled = false;
      }
      if (updated.spec is ClockedScheduleSpec) {
        final spec = updated.spec as ClockedScheduleSpec;
        if (spec.runOnce && !executedAt.isBefore(spec.runAt)) {
          enabled = false;
        }
      }
      next ??= executedAt;
      final nextVersion = entry.version + 1;

      await _send(['MULTI']);
      await _send([
        'HSET',
        key,
        'lastRunAt',
        executedAt.toIso8601String(),
        'nextRunAt',
        next.toIso8601String(),
        'lastJitterMs',
        jitter?.inMilliseconds.toString() ?? '',
        'lastError',
        lastError ?? '',
        'enabled',
        if (enabled) 'true' else 'false',
        'totalRunCount',
        updated.totalRunCount.toString(),
        'lastSuccessAt',
        updated.lastSuccessAt?.toIso8601String() ?? '',
        'lastErrorAt',
        updated.lastErrorAt?.toIso8601String() ?? '',
        'driftMs',
        updated.drift?.inMilliseconds.toString() ?? '',
        'version',
        nextVersion.toString(),
      ]);
      await _send([
        'ZADD',
        _indexKey,
        next.millisecondsSinceEpoch.toString(),
        id,
      ]);
      await _send(['DEL', lockKey]);
      final execResult = await _send(['EXEC']);
      watchActive = false;
      if (execResult == null) {
        await _send(['DEL', lockKey]);
        return;
      }
      committed = true;
    } finally {
      if (watchActive) {
        await _send(['UNWATCH']);
      }
      if (committed) {
        await _appendHistory(
          id: id,
          scheduledFor: scheduledFor,
          executedAt: executedAt,
          success: success && lastError == null,
          runDuration: runDuration,
          error: lastError,
        );
      }
    }
  }

  Future<void> _appendHistory({
    required String id,
    required DateTime scheduledFor,
    required DateTime executedAt,
    required bool success,
    Duration? runDuration,
    String? error,
  }) async {
    final key = '$namespace:schedule:$id:history';
    await _send([
      'XADD',
      key,
      '*',
      'scheduledAt',
      scheduledFor.toIso8601String(),
      'executedAt',
      executedAt.toIso8601String(),
      'success',
      if (success) 'true' else 'false',
      'durationMs',
      runDuration?.inMilliseconds.toString() ?? '',
      'error',
      error ?? '',
    ]);
    await _send(['XTRIM', key, 'MAXLEN', '~', '1000']);
  }
}
