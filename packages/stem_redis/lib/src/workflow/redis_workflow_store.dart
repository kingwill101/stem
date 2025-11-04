import 'dart:convert';

import 'package:redis/redis.dart';
import 'package:stem/stem.dart';

class RedisWorkflowStore implements WorkflowStore {
  RedisWorkflowStore._(
    this._connection,
    this._command, {
    required this.namespace,
  });

  final RedisConnection _connection;
  final Command _command;
  final String namespace;

  static Future<RedisWorkflowStore> connect(
    String uri, {
    String namespace = 'stem',
  }) async {
    final parsed = Uri.parse(uri);
    final host = parsed.host.isEmpty ? 'localhost' : parsed.host;
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
    return RedisWorkflowStore._(connection, command, namespace: namespace);
  }

  Future<dynamic> _send(List<Object?> cmd) => _command.send_object(cmd);

  String _runKey(String id) => '$namespace:wf:$id';
  String _stepsKey(String id) => '$namespace:wf:$id:steps';
  String _orderKey(String id) => '$namespace:wf:$id:order';
  String _topicKey(String topic) => '$namespace:wf:topic:$topic';
  String _dueKey() => '$namespace:wf:due';

  @override
  Future<String> createRun({
    required String workflow,
    required Map<String, Object?> params,
    String? parentRunId,
    Duration? ttl,
  }) async {
    final id = 'wf-${DateTime.now().microsecondsSinceEpoch}';
    await _send([
      'HSET',
      _runKey(id),
      'workflow',
      workflow,
      'status',
      WorkflowStatus.running.name,
      'params',
      jsonEncode(params),
    ]);
    await _send(['DEL', _stepsKey(id), _orderKey(id)]);
    return id;
  }

  @override
  Future<RunState?> get(String runId) async {
    final raw = await _send(['HGETALL', _runKey(runId)]) as List?;
    if (raw == null || raw.isEmpty) return null;
    final map = <String, String>{};
    for (var i = 0; i < raw.length; i += 2) {
      map[raw[i] as String] = raw[i + 1] as String;
    }
    final params = _decodeMap(map['params']);
    final suspension = _decodeMap(map['suspension_data']);
    final cursor = await _send(['HLEN', _stepsKey(runId)]) as int? ?? 0;
    return RunState(
      id: runId,
      workflow: map['workflow']!,
      status: WorkflowStatus.values.firstWhere(
        (value) => value.name == map['status'],
        orElse: () => WorkflowStatus.running,
      ),
      cursor: cursor,
      params: params,
      result: _decode(map['result']),
      waitTopic: _normalizeString(map['wait_topic']),
      resumeAt: _decodeMillis(map['resume_at']),
      lastError: _decodeMap(map['last_error']),
      suspensionData: suspension,
    );
  }

  @override
  Future<T?> readStep<T>(String runId, String stepName) async {
    final value = await _send(['HGET', _stepsKey(runId), stepName]);
    if (value == null) return null;
    return _decode(value as String) as T?;
  }

  @override
  Future<void> saveStep<T>(String runId, String stepName, T value) async {
    await _send(['HSET', _stepsKey(runId), stepName, jsonEncode(value)]);
    final score =
        await _send(['ZSCORE', _orderKey(runId), stepName]) as String?;
    if (score == null) {
      final next = await _send(['ZCARD', _orderKey(runId)]) as int? ?? 0;
      await _send(['ZADD', _orderKey(runId), next.toString(), stepName]);
    }
  }

  @override
  Future<void> suspendUntil(
    String runId,
    String stepName,
    DateTime when, {
    Map<String, Object?>? data,
  }) async {
    await _send([
      'HSET',
      _runKey(runId),
      'status',
      WorkflowStatus.suspended.name,
      'resume_at',
      when.millisecondsSinceEpoch.toString(),
      'wait_topic',
      '',
      'suspension_data',
      jsonEncode(data),
    ]);
    await _send([
      'ZADD',
      _dueKey(),
      when.millisecondsSinceEpoch.toString(),
      runId,
    ]);
  }

  @override
  Future<void> suspendOnTopic(
    String runId,
    String stepName,
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
  }) async {
    await _send([
      'HSET',
      _runKey(runId),
      'status',
      WorkflowStatus.suspended.name,
      'wait_topic',
      topic,
      'resume_at',
      deadline?.millisecondsSinceEpoch.toString() ?? '',
      'suspension_data',
      jsonEncode(data),
    ]);
    await _send(['SADD', _topicKey(topic), runId]);
    if (deadline != null) {
      await _send([
        'ZADD',
        _dueKey(),
        deadline.millisecondsSinceEpoch.toString(),
        runId,
      ]);
    }
  }

  @override
  Future<void> markRunning(String runId, {String? stepName}) async {
    await _send([
      'HSET',
      _runKey(runId),
      'status',
      WorkflowStatus.running.name,
      'resume_at',
      '',
      'wait_topic',
      '',
    ]);
    await _send(['ZREM', _dueKey(), runId]);
  }

  @override
  Future<void> markCompleted(String runId, Object? result) async {
    await _send([
      'HSET',
      _runKey(runId),
      'status',
      WorkflowStatus.completed.name,
      'result',
      jsonEncode(result),
      'suspension_data',
      '',
    ]);
    await _send(['ZREM', _dueKey(), runId]);
  }

  @override
  Future<void> markFailed(
    String runId,
    Object error,
    StackTrace stack, {
    bool terminal = false,
  }) async {
    await _send([
      'HSET',
      _runKey(runId),
      'status',
      (terminal ? WorkflowStatus.failed : WorkflowStatus.running).name,
      'last_error',
      jsonEncode({'error': error.toString(), 'stack': stack.toString()}),
    ]);
  }

  @override
  Future<void> markResumed(String runId, {Map<String, Object?>? data}) async {
    final run = await get(runId);
    final waitTopic = run?.waitTopic;
    await _send([
      'HSET',
      _runKey(runId),
      'status',
      WorkflowStatus.running.name,
      'resume_at',
      '',
      'wait_topic',
      '',
      'suspension_data',
      jsonEncode(data),
    ]);
    await _send(['ZREM', _dueKey(), runId]);
    if (waitTopic != null) {
      await _send(['SREM', _topicKey(waitTopic), runId]);
    }
  }

  @override
  Future<List<String>> dueRuns(DateTime now, {int limit = 256}) async {
    final entries =
        await _send([
              'ZRANGEBYSCORE',
              _dueKey(),
              '-inf',
              now.millisecondsSinceEpoch.toString(),
              'LIMIT',
              '0',
              limit.toString(),
            ])
            as List?;
    if (entries == null) return const [];
    final ids = entries.cast<String>();
    if (ids.isNotEmpty) {
      await _send(['ZREM', _dueKey(), ...ids]);
    }
    return ids;
  }

  @override
  Future<List<String>> runsWaitingOn(String topic, {int limit = 256}) async {
    final entries = await _send(['SMEMBERS', _topicKey(topic)]) as List?;
    if (entries == null) return const [];
    return entries.cast<String>().take(limit).toList(growable: false);
  }

  @override
  Future<void> cancel(String runId, {String? reason}) async {
    final state = await get(runId);
    await _send([
      'HSET',
      _runKey(runId),
      'status',
      WorkflowStatus.cancelled.name,
      'resume_at',
      '',
      'wait_topic',
      '',
      'suspension_data',
      '',
    ]);
    await _send(['ZREM', _dueKey(), runId]);
    final waitTopic = state?.waitTopic;
    if (waitTopic != null) {
      await _send(['SREM', _topicKey(waitTopic), runId]);
    }
  }

  @override
  Future<void> rewindToStep(String runId, String stepName) async {
    final names = await _send(['ZRANGE', _orderKey(runId), '0', '-1']) as List?;
    if (names == null) return;
    final index = names.cast<String>().indexOf(stepName);
    if (index == -1) return;
    final keep = names.cast<String>().take(index).toList();
    final stepValues = <String, String>{};
    for (final name in keep) {
      final value = await _send(['HGET', _stepsKey(runId), name]);
      if (value != null) {
        stepValues[name] = value as String;
      }
    }
    await _send(['DEL', _stepsKey(runId), _orderKey(runId)]);
    var score = 0;
    for (final entry in stepValues.entries) {
      await _send(['HSET', _stepsKey(runId), entry.key, entry.value]);
      await _send(['ZADD', _orderKey(runId), score.toString(), entry.key]);
      score += 1;
    }
  }

  @override
  Future<List<RunState>> listRuns({
    String? workflow,
    WorkflowStatus? status,
    int limit = 50,
  }) async {
    final ids = <String>[];
    var cursor = '0';
    final pattern = '$namespace:wf:wf-*';
    do {
      final result =
          await _send(['SCAN', cursor, 'MATCH', pattern, 'COUNT', '100'])
              as List;
      cursor = result[0] as String;
      final keys = (result[1] as List).cast<String>();
      for (final key in keys) {
        final parts = key.split(':');
        if (parts.length != 3) continue;
        final id = parts.last;
        if (!ids.contains(id)) {
          ids.add(id);
        }
      }
    } while (cursor != '0' && ids.length < limit * 3);

    final states = <RunState>[];
    ids.sort((a, b) => b.compareTo(a));
    for (final id in ids) {
      final state = await get(id);
      if (state == null) continue;
      if (workflow != null && state.workflow != workflow) continue;
      if (status != null && state.status != status) continue;
      states.add(state);
      if (states.length >= limit) break;
    }
    return states;
  }

  @override
  Future<List<WorkflowStepEntry>> listSteps(String runId) async {
    final names = await _send(['ZRANGE', _orderKey(runId), '0', '-1']) as List?;
    if (names == null) return const [];
    final entries = <WorkflowStepEntry>[];
    var index = 0;
    for (final rawName in names.cast<String>()) {
      final value = await _send(['HGET', _stepsKey(runId), rawName]);
      entries.add(
        WorkflowStepEntry(
          name: rawName,
          value: value != null ? _decode(value as String) : null,
          position: index,
        ),
      );
      index += 1;
    }
    return entries;
  }

  Future<void> close() async {
    await _connection.close();
  }

  Map<String, Object?> _decodeMap(String? value) {
    if (value == null || value.isEmpty) return const {};
    final decoded = jsonDecode(value);
    return decoded is Map ? decoded.cast<String, Object?>() : const {};
  }

  Object? _decode(String? value) {
    if (value == null || value.isEmpty) return null;
    return jsonDecode(value);
  }

  DateTime? _decodeMillis(String? value) {
    if (value == null || value.isEmpty) return null;
    final millis = int.tryParse(value);
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  String? _normalizeString(String? value) {
    if (value == null || value.isEmpty) return null;
    return value;
  }
}
