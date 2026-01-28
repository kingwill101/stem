import 'dart:convert';
import 'dart:io';

import 'package:redis/redis.dart';
import 'package:stem/stem.dart';

/// Redis-backed implementation of [WorkflowStore].
class RedisWorkflowStore implements WorkflowStore {
  RedisWorkflowStore._(
    this._connection,
    this._command, {
    required this.namespace,
    required WorkflowClock clock,
  }) : _clock = clock;

  final RedisConnection _connection;
  final Command _command;

  /// Namespace used to scope workflow keys.
  final String namespace;
  final WorkflowClock _clock;
  int _idCounter = 0;

  /// Connects to Redis and returns a workflow store instance.
  static Future<RedisWorkflowStore> connect(
    String uri, {
    String namespace = 'stem',
    WorkflowClock clock = const SystemWorkflowClock(),
    TlsConfig? tls,
  }) async {
    final parsed = Uri.parse(uri);
    final host = parsed.host.isEmpty ? 'localhost' : parsed.host;
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
          component: 'redis workflow store',
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
    return RedisWorkflowStore._(
      connection,
      command,
      namespace: namespace,
      clock: clock,
    );
  }

  Future<dynamic> _send(List<Object?> cmd) => _command.send_object(cmd);

  String _runKey(String id) => '$namespace:wf:$id';
  String _stepsKey(String id) => '$namespace:wf:$id:steps';
  String _orderKey(String id) => '$namespace:wf:$id:order';
  String _topicKey(String topic) => '$namespace:wf:topic:$topic';
  String _dueKey() => '$namespace:wf:due';
  String _watchersHashKey() => '$namespace:wf:watchers';
  String _watchersTopicKey(String topic) =>
      '$namespace:wf:watchers:topic:$topic';
  String _runKeyPrefix() => '$namespace:wf:';

  Map<String, Object?> _prepareSuspensionData(
    Map<String, Object?>? source, {
    DateTime? resumeAt,
    DateTime? deadline,
    String? topic,
  }) {
    final result = <String, Object?>{};
    if (source != null) {
      result.addAll(source);
    }
    if (resumeAt != null && !result.containsKey('resumeAt')) {
      result['resumeAt'] = resumeAt.toIso8601String();
    }
    if (deadline != null && !result.containsKey('deadline')) {
      result['deadline'] = deadline.toIso8601String();
    }
    if (topic != null && topic.isNotEmpty && !result.containsKey('topic')) {
      result['topic'] = topic;
    }
    return result;
  }

  static const _luaRegisterWatcher = '''
local runKey = KEYS[1]
local watchersHash = KEYS[2]
local topicSetKey = KEYS[3]
local dueKey = KEYS[4]
local watchersTopicKey = KEYS[5]

local runId = ARGV[1]
local suspensionData = ARGV[2]
local deadlineMs = ARGV[3]
local nowIso = ARGV[4]
local nowScore = tonumber(ARGV[5])
local watcherPayload = ARGV[6]
local status = ARGV[7]
local topic = ARGV[8]

local existing = redis.call('HGET', watchersHash, runId)
if existing then
  local parsed = cjson.decode(existing)
  if parsed['watchersTopicKey'] then
    redis.call('ZREM', parsed['watchersTopicKey'], runId)
  end
  if parsed['topicSetKey'] then
    redis.call('SREM', parsed['topicSetKey'], runId)
  end
end

redis.call('HSET', runKey,
  'status', status,
  'wait_topic', topic,
  'resume_at', deadlineMs,
  'suspension_data', suspensionData,
  'updated_at', nowIso)

redis.call('HSET', watchersHash, runId, watcherPayload)
redis.call('ZADD', watchersTopicKey, nowScore, runId)
redis.call('SADD', topicSetKey, runId)

if deadlineMs ~= '' then
  redis.call('ZADD', dueKey, deadlineMs, runId)
else
  redis.call('ZREM', dueKey, runId)
end

return 1
''';

  static const _luaResolveWatchers = '''
local watchersHash = KEYS[1]
local dueKey = KEYS[2]
local watchersTopicKey = KEYS[3]
local topicSetKey = KEYS[4]

local runKeyPrefix = ARGV[1]
local payloadJson = ARGV[2]
local topic = ARGV[3]
local limit = tonumber(ARGV[4])
local nowIso = ARGV[5]
local runningStatus = ARGV[6]

local payload = cjson.decode(payloadJson)
local members = redis.call('ZRANGE', watchersTopicKey, 0, limit - 1)
local results = {}
for _, runId in ipairs(members) do
  local rawWatcher = redis.call('HGET', watchersHash, runId)
  if rawWatcher then
    local watcher = cjson.decode(rawWatcher)
    redis.call('HDEL', watchersHash, runId)
    local watcherTopicKey = watcher['watchersTopicKey'] or watchersTopicKey
    local watcherTopicSet = watcher['topicSetKey'] or topicSetKey
    redis.call('ZREM', watcherTopicKey, runId)
    redis.call('SREM', watcherTopicSet, runId)
    redis.call('ZREM', dueKey, runId)
    local metadata = watcher['data'] or {}
    metadata['type'] = 'event'
    metadata['topic'] = topic
    metadata['payload'] = payload
    metadata['step'] = metadata['step'] or watcher['stepName']
    metadata['iterationStep'] = metadata['iterationStep'] or watcher['stepName']
    metadata['deliveredAt'] = nowIso
    local runKey = runKeyPrefix .. runId
    redis.call('HSET', runKey,
      'status', runningStatus,
      'wait_topic', '',
      'resume_at', '',
      'suspension_data', cjson.encode(metadata),
      'updated_at', nowIso)
    table.insert(results, cjson.encode({
      runId = runId,
      stepName = watcher['stepName'],
      topic = topic,
      resumeData = metadata
    }))
  else
    redis.call('ZREM', watchersTopicKey, runId)
    redis.call('SREM', topicSetKey, runId)
    redis.call('ZREM', dueKey, runId)
  end
end
return results
''';

  static const _luaRemoveWatcher = '''
local watchersHash = KEYS[1]
local dueKey = KEYS[2]

local runId = ARGV[1]

local existing = redis.call('HGET', watchersHash, runId)
if not existing then
  return 0
end

local watcher = cjson.decode(existing)
redis.call('HDEL', watchersHash, runId)
if watcher['watchersTopicKey'] then
  redis.call('ZREM', watcher['watchersTopicKey'], runId)
end
if watcher['topicSetKey'] then
  redis.call('SREM', watcher['topicSetKey'], runId)
end
redis.call('ZREM', dueKey, runId)
return 1
''';

  static const _luaClaimRun = '''
local runKey = KEYS[1]

local nowMs = tonumber(ARGV[1])
local ownerId = ARGV[2]
local leaseMs = tonumber(ARGV[3])
local runningStatus = ARGV[4]
local nowIso = ARGV[5]

local status = redis.call('HGET', runKey, 'status')
if not status or status ~= runningStatus then
  return 0
end

local waitTopic = redis.call('HGET', runKey, 'wait_topic')
if waitTopic and waitTopic ~= '' then
  return 0
end

local currentOwner = redis.call('HGET', runKey, 'owner_id')
local lease = redis.call('HGET', runKey, 'lease_expires_at')
if currentOwner and currentOwner ~= '' and currentOwner ~= ownerId then
  if lease and lease ~= '' and tonumber(lease) > nowMs then
    return 0
  end
end

redis.call('HSET', runKey,
  'owner_id', ownerId,
  'lease_expires_at', tostring(nowMs + leaseMs),
  'updated_at', nowIso)
return 1
''';

  static const _luaRenewRun = '''
local runKey = KEYS[1]

local nowMs = tonumber(ARGV[1])
local ownerId = ARGV[2]
local leaseMs = tonumber(ARGV[3])
local runningStatus = ARGV[4]
local nowIso = ARGV[5]

local status = redis.call('HGET', runKey, 'status')
if not status or status ~= runningStatus then
  return 0
end

local currentOwner = redis.call('HGET', runKey, 'owner_id')
if not currentOwner or currentOwner ~= ownerId then
  return 0
end

redis.call('HSET', runKey,
  'lease_expires_at', tostring(nowMs + leaseMs),
  'updated_at', nowIso)
return 1
''';

  static const _luaReleaseRun = '''
local runKey = KEYS[1]

local ownerId = ARGV[1]
local nowIso = ARGV[2]

local currentOwner = redis.call('HGET', runKey, 'owner_id')
if not currentOwner or currentOwner ~= ownerId then
  return 0
end

redis.call('HSET', runKey,
  'owner_id', '',
  'lease_expires_at', '',
  'updated_at', nowIso)
return 1
''';

  String _baseStepName(String name) {
    final hashIndex = name.indexOf('#');
    if (hashIndex == -1) return name;
    return name.substring(0, hashIndex);
  }

  @override
  Future<String> createRun({
    required String workflow,
    required Map<String, Object?> params,
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) async {
    final now = _clock.now();
    final nowIso = now.toIso8601String();
    final id = 'wf-${now.microsecondsSinceEpoch}-${_idCounter++}';
    final command = [
      'HSET',
      _runKey(id),
      'workflow',
      workflow,
      'status',
      WorkflowStatus.running.name,
      'params',
      jsonEncode(params),
      'created_at',
      nowIso,
      'updated_at',
      nowIso,
      'owner_id',
      '',
      'lease_expires_at',
      '',
    ];
    if (cancellationPolicy != null && !cancellationPolicy.isEmpty) {
      command
        ..add('cancellation_policy')
        ..add(jsonEncode(cancellationPolicy.toJson()));
    }
    await _send(command);
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
    final createdAt = _decodeDateTime(map['created_at']);
    final updatedAt = _decodeDateTime(map['updated_at']);
    WorkflowCancellationPolicy? policy;
    final policyRaw = map['cancellation_policy'];
    if (policyRaw != null && policyRaw.isNotEmpty) {
      policy = WorkflowCancellationPolicy.fromJson(_decode(policyRaw));
      if (policy != null && policy.isEmpty) {
        policy = null;
      }
    }
    Map<String, Object?>? cancellationData;
    final cancellationRaw = map['cancellation_data'];
    if (cancellationRaw != null && cancellationRaw.isNotEmpty) {
      final decoded = _decode(cancellationRaw);
      if (decoded is Map) {
        cancellationData = decoded.cast<String, Object?>();
      }
    }
    final stepNames = await _send(['HKEYS', _stepsKey(runId)]) as List? ?? [];
    final cursor = stepNames.cast<String>().map(_baseStepName).toSet().length;
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
      createdAt: createdAt,
      updatedAt: updatedAt == DateTime.fromMillisecondsSinceEpoch(0)
          ? null
          : updatedAt,
      ownerId: _normalizeString(map['owner_id']),
      leaseExpiresAt: _decodeMillis(map['lease_expires_at']),
      cancellationPolicy: policy,
      cancellationData: cancellationData,
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
    final nowIso = _clock.now().toIso8601String();
    await _send(['HSET', _stepsKey(runId), stepName, jsonEncode(value)]);
    final score =
        await _send(['ZSCORE', _orderKey(runId), stepName]) as String?;
    if (score == null) {
      final next = await _send(['ZCARD', _orderKey(runId)]) as int? ?? 0;
      await _send(['ZADD', _orderKey(runId), next.toString(), stepName]);
    }
    await _send(['HSET', _runKey(runId), 'updated_at', nowIso]);
  }

  @override
  Future<void> suspendUntil(
    String runId,
    String stepName,
    DateTime when, {
    Map<String, Object?>? data,
  }) async {
    final metadata = _prepareSuspensionData(data, resumeAt: when);
    final now = _clock.now().toIso8601String();
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
      jsonEncode(metadata),
      'updated_at',
      now,
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
    final metadata = _prepareSuspensionData(
      data,
      resumeAt: deadline,
      deadline: deadline,
      topic: topic,
    );
    final now = _clock.now().toIso8601String();
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
      jsonEncode(metadata),
      'updated_at',
      now,
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
  Future<void> registerWatcher(
    String runId,
    String stepName,
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
  }) async {
    final now = _clock.now();
    final nowIso = now.toIso8601String();
    final nowMillis = now.millisecondsSinceEpoch.toString();
    final metadata = _prepareSuspensionData(
      data,
      resumeAt: deadline,
      deadline: deadline,
      topic: topic,
    );
    final deadlineMillis = deadline != null
        ? deadline.millisecondsSinceEpoch.toString()
        : '';
    final suspensionData = jsonEncode(metadata);
    final watcherPayload = jsonEncode({
      'runId': runId,
      'stepName': stepName,
      'topic': topic,
      'data': metadata,
      'createdAt': nowIso,
      if (deadline != null) 'deadline': deadline.toIso8601String(),
      'watchersTopicKey': _watchersTopicKey(topic),
      'topicSetKey': _topicKey(topic),
    });
    await suspendOnTopic(
      runId,
      stepName,
      topic,
      deadline: deadline,
      data: metadata,
    );
    await _send([
      'EVAL',
      _luaRegisterWatcher,
      '5',
      _runKey(runId),
      _watchersHashKey(),
      _topicKey(topic),
      _dueKey(),
      _watchersTopicKey(topic),
      runId,
      suspensionData,
      deadlineMillis,
      nowIso,
      nowMillis,
      watcherPayload,
      WorkflowStatus.suspended.name,
      topic,
    ]);
  }

  @override
  Future<void> markRunning(String runId, {String? stepName}) async {
    final now = _clock.now().toIso8601String();
    await _removeWatcher(runId);
    await _send([
      'HSET',
      _runKey(runId),
      'status',
      WorkflowStatus.running.name,
      'resume_at',
      '',
      'wait_topic',
      '',
      'updated_at',
      now,
    ]);
    await _send(['ZREM', _dueKey(), runId]);
  }

  @override
  Future<void> markCompleted(String runId, Object? result) async {
    final now = _clock.now().toIso8601String();
    await _removeWatcher(runId);
    await _send([
      'HSET',
      _runKey(runId),
      'status',
      WorkflowStatus.completed.name,
      'result',
      jsonEncode(result),
      'suspension_data',
      '',
      'owner_id',
      '',
      'lease_expires_at',
      '',
      'updated_at',
      now,
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
    final now = _clock.now().toIso8601String();
    if (terminal) {
      await _removeWatcher(runId);
    }
    await _send([
      'HSET',
      _runKey(runId),
      'status',
      (terminal ? WorkflowStatus.failed : WorkflowStatus.running).name,
      'last_error',
      jsonEncode({'error': error.toString(), 'stack': stack.toString()}),
      'updated_at',
      now,
    ]);
    if (terminal) {
      await _send([
        'HSET',
        _runKey(runId),
        'owner_id',
        '',
        'lease_expires_at',
        '',
      ]);
    }
  }

  @override
  Future<void> markResumed(String runId, {Map<String, Object?>? data}) async {
    final run = await get(runId);
    final waitTopic = run?.waitTopic;
    final now = _clock.now().toIso8601String();
    await _removeWatcher(runId);
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
      'updated_at',
      now,
    ]);
    await _send(['ZREM', _dueKey(), runId]);
    if (waitTopic != null) {
      await _send(['SREM', _topicKey(waitTopic), runId]);
    }
  }

  @override
  Future<bool> claimRun(
    String runId, {
    required String ownerId,
    Duration leaseDuration = const Duration(seconds: 30),
  }) async {
    final now = _clock.now();
    final nowMs = now.millisecondsSinceEpoch;
    final nowIso = now.toIso8601String();
    final result = await _send([
      'EVAL',
      _luaClaimRun,
      '1',
      _runKey(runId),
      nowMs.toString(),
      ownerId,
      leaseDuration.inMilliseconds.toString(),
      WorkflowStatus.running.name,
      nowIso,
    ]);
    return result == 1 || result == '1';
  }

  @override
  Future<bool> renewRunLease(
    String runId, {
    required String ownerId,
    Duration leaseDuration = const Duration(seconds: 30),
  }) async {
    final now = _clock.now();
    final nowMs = now.millisecondsSinceEpoch;
    final nowIso = now.toIso8601String();
    final result = await _send([
      'EVAL',
      _luaRenewRun,
      '1',
      _runKey(runId),
      nowMs.toString(),
      ownerId,
      leaseDuration.inMilliseconds.toString(),
      WorkflowStatus.running.name,
      nowIso,
    ]);
    return result == 1 || result == '1';
  }

  @override
  Future<void> releaseRun(String runId, {required String ownerId}) async {
    final nowIso = _clock.now().toIso8601String();
    await _send([
      'EVAL',
      _luaReleaseRun,
      '1',
      _runKey(runId),
      ownerId,
      nowIso,
    ]);
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
    final ordered =
        await _send([
              'ZRANGE',
              _watchersTopicKey(topic),
              '0',
              (limit - 1).toString(),
            ])
            as List?;
    if (ordered != null && ordered.isNotEmpty) {
      return ordered.cast<String>().take(limit).toList(growable: false);
    }
    final entries = await _send(['SMEMBERS', _topicKey(topic)]) as List?;
    if (entries == null || entries.isEmpty) return const [];
    return entries.cast<String>().take(limit).toList(growable: false);
  }

  @override
  Future<List<WorkflowWatcherResolution>> resolveWatchers(
    String topic,
    Map<String, Object?> payload, {
    int limit = 256,
  }) async {
    final nowIso = _clock.now().toIso8601String();
    final results =
        await _send([
              'EVAL',
              _luaResolveWatchers,
              '4',
              _watchersHashKey(),
              _dueKey(),
              _watchersTopicKey(topic),
              _topicKey(topic),
              _runKeyPrefix(),
              jsonEncode(payload),
              topic,
              limit.toString(),
              nowIso,
              WorkflowStatus.running.name,
            ])
            as List?;
    if (results == null || results.isEmpty) {
      return const [];
    }
    final resolutions = <WorkflowWatcherResolution>[];
    for (final raw in results.cast<String>()) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final resume = decoded['resumeData'];
      resolutions.add(
        WorkflowWatcherResolution(
          runId: decoded['runId'] as String,
          stepName: decoded['stepName'] as String,
          topic: decoded['topic'] as String,
          resumeData: resume is Map
              ? resume.cast<String, Object?>()
              : const <String, Object?>{},
        ),
      );
    }
    return resolutions;
  }

  @override
  Future<List<WorkflowWatcher>> listWatchers(
    String topic, {
    int limit = 256,
  }) async {
    final members =
        await _send([
              'ZRANGE',
              _watchersTopicKey(topic),
              '0',
              (limit - 1).toString(),
            ])
            as List?;
    if (members == null || members.isEmpty) {
      return const [];
    }
    final watchers = <WorkflowWatcher>[];
    for (final runId in members.cast<String>()) {
      final raw = await _send(['HGET', _watchersHashKey(), runId]) as String?;
      if (raw == null || raw.isEmpty) {
        continue;
      }
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final createdAtIso = decoded['createdAt'] as String?;
      final deadlineIso = decoded['deadline'] as String?;
      final data = decoded['data'];
      watchers.add(
        WorkflowWatcher(
          runId: runId,
          stepName: decoded['stepName'] as String,
          topic: (decoded['topic'] as String?) ?? topic,
          createdAt: createdAtIso != null
              ? DateTime.tryParse(createdAtIso) ??
                    DateTime.fromMillisecondsSinceEpoch(0)
              : DateTime.fromMillisecondsSinceEpoch(0),
          deadline: deadlineIso != null ? DateTime.tryParse(deadlineIso) : null,
          data: data is Map ? data.cast<String, Object?>() : const {},
        ),
      );
    }
    return watchers;
  }

  @override
  Future<void> cancel(String runId, {String? reason}) async {
    final state = await get(runId);
    final now = _clock.now();
    final cancellationData = <String, Object?>{
      'reason': reason ?? 'cancelled',
      'cancelledAt': now.toIso8601String(),
    };
    await _removeWatcher(runId);
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
      'cancellation_data',
      jsonEncode(cancellationData),
      'owner_id',
      '',
      'lease_expires_at',
      '',
      'updated_at',
      now.toIso8601String(),
    ]);
    await _send(['ZREM', _dueKey(), runId]);
    final waitTopic = state?.waitTopic;
    if (waitTopic != null) {
      await _send(['SREM', _topicKey(waitTopic), runId]);
    }
  }

  @override
  Future<void> rewindToStep(String runId, String stepName) async {
    await _removeWatcher(runId);
    final names = await _send(['ZRANGE', _orderKey(runId), '0', '-1']) as List?;
    if (names == null) return;
    final baseIndexMap = <String, int>{};
    var nextIndex = 0;
    final entryIndexes = <int>[];
    final castNames = names.cast<String>();
    for (final name in castNames) {
      final base = _baseStepName(name);
      baseIndexMap.putIfAbsent(base, () => nextIndex++);
      entryIndexes.add(baseIndexMap[base]!);
    }
    final targetIndex = baseIndexMap[stepName];
    if (targetIndex == null) return;

    final keep = <String>{};
    for (var i = 0; i < castNames.length; i++) {
      final baseIndex = entryIndexes[i];
      if (baseIndex < targetIndex) {
        keep.add(castNames[i]);
      } else {
        break;
      }
    }

    for (final name in castNames) {
      if (!keep.contains(name)) {
        await _send(['HDEL', _stepsKey(runId), name]);
        await _send(['ZREM', _orderKey(runId), name]);
      }
    }

    const iterations = 0;
    await _send([
      'HSET',
      _runKey(runId),
      'status',
      WorkflowStatus.suspended.name,
      'wait_topic',
      '',
      'resume_at',
      '',
      'suspension_data',
      jsonEncode({
        'step': stepName,
        'iteration': iterations,
        'iterationStep': stepName,
      }),
    ]);
  }

  @override
  Future<List<RunState>> listRuns({
    String? workflow,
    WorkflowStatus? status,
    int limit = 50,
    int offset = 0,
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
    var skipped = 0;
    for (final id in ids) {
      final state = await get(id);
      if (state == null) continue;
      if (workflow != null && state.workflow != workflow) continue;
      if (status != null && state.status != status) continue;
      if (skipped < offset) {
        skipped += 1;
        continue;
      }
      states.add(state);
      if (states.length >= limit) break;
    }
    return states;
  }

  @override
  Future<List<String>> listRunnableRuns({
    DateTime? now,
    int limit = 50,
    int offset = 0,
  }) async {
    final resolvedNow = now ?? _clock.now();
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

    ids.sort((a, b) => b.compareTo(a));
    final runnable = <String>[];
    var skipped = 0;
    for (final id in ids) {
      final state = await get(id);
      if (state == null) continue;
      if (state.status != WorkflowStatus.running) continue;
      if (state.waitTopic != null) continue;
      final lease = state.leaseExpiresAt;
      if (lease != null && lease.isAfter(resolvedNow)) {
        if (state.ownerId != null && state.ownerId!.isNotEmpty) {
          continue;
        }
      }
      if (skipped < offset) {
        skipped += 1;
        continue;
      }
      runnable.add(id);
      if (runnable.length >= limit) break;
    }
    return runnable;
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

  /// Closes the workflow store and releases Redis resources.
  Future<void> close() async {
    await _connection.close();
  }

  Future<void> _removeWatcher(String runId) async {
    await _send([
      'EVAL',
      _luaRemoveWatcher,
      '2',
      _watchersHashKey(),
      _dueKey(),
      runId,
    ]);
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

  DateTime _decodeDateTime(String? value) {
    if (value == null || value.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  String? _normalizeString(String? value) {
    if (value == null || value.isEmpty) return null;
    return value;
  }
}
