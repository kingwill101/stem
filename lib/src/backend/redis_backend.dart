import 'dart:async';
import 'dart:convert';

import 'package:redis/redis.dart';

import '../core/contracts.dart';

/// Redis-backed implementation of [ResultBackend].
class RedisResultBackend implements ResultBackend {
  RedisResultBackend._(
    this._connection,
    this._command, {
    this.namespace = 'stem',
    this.defaultTtl = const Duration(days: 1),
    this.groupDefaultTtl = const Duration(days: 1),
  });

  final RedisConnection _connection;
  final Command _command;
  final String namespace;
  final Duration defaultTtl;
  final Duration groupDefaultTtl;

  final Map<String, StreamController<TaskStatus>> _watchers = {};
  bool _closed = false;

  static Future<RedisResultBackend> connect(
    String uri, {
    String namespace = 'stem',
    Duration defaultTtl = const Duration(days: 1),
    Duration groupDefaultTtl = const Duration(days: 1),
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

    return RedisResultBackend._(
      connection,
      command,
      namespace: namespace,
      defaultTtl: defaultTtl,
      groupDefaultTtl: groupDefaultTtl,
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final controller in _watchers.values) {
      await controller.close();
    }
    _watchers.clear();
    await _connection.close();
  }

  String _taskKey(String id) => '$namespace:result:$id';
  String _groupKey(String id) => '$namespace:group:$id';
  String _groupResultsKey(String id) => '$namespace:group:$id:results';

  Future<dynamic> _send(List<Object> command) => _command.send_object(command);

  @override
  Future<void> set(
    String taskId,
    TaskState state, {
    Object? payload,
    TaskError? error,
    int attempt = 0,
    Map<String, Object?> meta = const {},
    Duration? ttl,
  }) async {
    final status = TaskStatus(
      id: taskId,
      state: state,
      payload: payload,
      error: error,
      attempt: attempt,
      meta: meta,
    );
    final encoded = jsonEncode(status.toJson());
    final key = _taskKey(taskId);
    final expire = (ttl ?? defaultTtl).inMilliseconds;
    await _send(['SET', key, encoded, 'PX', expire.toString()]);
    _watchers[taskId]?.add(status);
  }

  @override
  Future<TaskStatus?> get(String taskId) async {
    final raw = await _send(['GET', _taskKey(taskId)]);
    if (raw == null) return null;
    final map = jsonDecode(raw as String) as Map<String, Object?>;
    return TaskStatus.fromJson(map);
  }

  @override
  Stream<TaskStatus> watch(String taskId) {
    final controller = _watchers.putIfAbsent(
      taskId,
      () => StreamController<TaskStatus>.broadcast(
        onCancel: () {
          if (!(_watchers[taskId]?.hasListener ?? false)) {
            _watchers.remove(taskId)?.close();
          }
        },
      ),
    );
    return controller.stream;
  }

  @override
  Future<void> initGroup(GroupDescriptor descriptor) async {
    final ttl = descriptor.ttl ?? groupDefaultTtl;
    final metadata = {
      'id': descriptor.id,
      'expected': descriptor.expected,
      'meta': descriptor.meta,
    };
    await _send([
      'SET',
      _groupKey(descriptor.id),
      jsonEncode(metadata),
      'PX',
      ttl.inMilliseconds.toString(),
    ]);
    await _send(['DEL', _groupResultsKey(descriptor.id)]);
    await _send([
      'PEXPIRE',
      _groupResultsKey(descriptor.id),
      ttl.inMilliseconds.toString(),
    ]);
  }

  @override
  Future<GroupStatus?> addGroupResult(String groupId, TaskStatus status) async {
    final descriptorRaw = await _send(['GET', _groupKey(groupId)]);
    if (descriptorRaw == null) return null;

    final ttl = await _send(['PTTL', _groupKey(groupId)]);
    final ttlMs = _asInt(ttl);
    if (ttlMs <= 0) return null;

    await _send([
      'HSET',
      _groupResultsKey(groupId),
      status.id,
      jsonEncode(status.toJson()),
    ]);
    await _send(['PEXPIRE', _groupResultsKey(groupId), ttlMs.toString()]);

    return getGroup(groupId);
  }

  @override
  Future<GroupStatus?> getGroup(String groupId) async {
    final descriptorRaw = await _send(['GET', _groupKey(groupId)]);
    if (descriptorRaw == null) return null;

    final descriptor =
        jsonDecode(descriptorRaw as String) as Map<String, Object?>;
    final expected = descriptor['expected'] as num;
    final meta =
        (descriptor['meta'] as Map?)?.cast<String, Object?>() ?? const {};

    final resultsRaw =
        await _send(['HGETALL', _groupResultsKey(groupId)]) as List?;
    final results = <String, TaskStatus>{};
    if (resultsRaw != null && resultsRaw.isNotEmpty) {
      for (var i = 0; i < resultsRaw.length; i += 2) {
        final key = resultsRaw[i] as String;
        final value = resultsRaw[i + 1] as String;
        results[key] = TaskStatus.fromJson(
          jsonDecode(value) as Map<String, Object?>,
        );
      }
    }

    return GroupStatus(
      id: groupId,
      expected: expected.toInt(),
      results: results,
      meta: meta,
    );
  }

  @override
  Future<void> expire(String taskId, Duration ttl) async {
    await _send(['PEXPIRE', _taskKey(taskId), ttl.inMilliseconds.toString()]);
  }

  int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is List && value.isNotEmpty) return _asInt(value.first);
    return 0;
  }
}
