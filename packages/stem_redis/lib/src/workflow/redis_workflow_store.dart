// Public constructor names intentionally initialize private implementation
// fields to preserve the package API.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:io';

import 'package:redis/redis.dart';
import 'package:stem/stem.dart';
import 'package:uuid/uuid.dart';

/// Redis-backed implementation of [WorkflowStore].
class RedisWorkflowStore
    implements
        WorkflowStore,
        WorkflowTerminalStore,
        FencedWorkflowStore,
        WorkflowJournalStore {
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
  String _journalKey(String id, WorkflowJournalKind kind) =>
      '$namespace:wf:$id:journal:${kind.name}';
  String _compensationOrderKey(String id) =>
      '$namespace:wf:$id:journal:compensation:order';
  String _compensationSequenceKey(String id) =>
      '$namespace:wf:$id:journal:compensation:sequence';
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
local currentStatus = redis.call('HGET', runKey, 'status')
if currentStatus ~= ARGV[9] and currentStatus ~= ARGV[10] then return 0 end

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
    local runKey = runKeyPrefix .. runId
    local status = redis.call('HGET', runKey, 'status')
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
    if status == runningStatus or status == ARGV[7] then
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
    end
  else
    redis.call('ZREM', watchersTopicKey, runId)
    redis.call('SREM', topicSetKey, runId)
    redis.call('ZREM', dueKey, runId)
  end
end
return results
''';

  static const _luaCreateRun = '''
local runKey = KEYS[1]
local stepsKey = KEYS[2]
local orderKey = KEYS[3]

if redis.call('EXISTS', runKey) == 1 then
  return 0
end

redis.call('DEL', stepsKey, orderKey)
redis.call('HSET', runKey,
  'workflow', ARGV[1],
  'status', ARGV[2],
  'params', ARGV[3],
  'created_at', ARGV[4],
  'updated_at', ARGV[5],
  'owner_id', ARGV[6],
  'lease_expires_at', ARGV[7],
  'execution_id', '')

if ARGV[8] ~= '' then
  redis.call('HSET', runKey, 'cancellation_policy', ARGV[8])
end

return 1
''';

  // Shared by ordinary checkpoints and fenced journal commits.
  static const _luaWriteCheckpoint = '''
local function writeCheckpoint(stepsKey, orderKey, name, value)
  redis.call('HSET', stepsKey, name, value)
  if not redis.call('ZSCORE', orderKey, name) then
    redis.call('ZADD', orderKey, redis.call('ZCARD', orderKey), name)
  end
end
''';

  static const _luaSaveStep =
      '''
$_luaWriteCheckpoint
if redis.call('EXISTS', KEYS[1]) == 0 then return 0 end
writeCheckpoint(KEYS[2], KEYS[3], ARGV[1], ARGV[2])
redis.call('HSET', KEYS[1], 'updated_at', ARGV[3])
return 1
''';

  static const _luaCommitJournal =
      '''
$_luaWriteCheckpoint
local runKey = KEYS[1]
local journalKey = KEYS[2]
local compensationKey = KEYS[3]
local compensationOrderKey = KEYS[4]
local compensationSequenceKey = KEYS[5]
local kind = ARGV[1]
local name = ARGV[2]
local expected = tonumber(ARGV[3])
local newRevision = tonumber(ARGV[4])
local executionId = ARGV[5]
local data = ARGV[6]
local checkpointValue = ARGV[7]
local hasCheckpoint = ARGV[8] == '1'
local hasCompensation = ARGV[9] == '1'
local runningStatus = ARGV[10]
local failedStatus = ARGV[11]
local status = redis.call('HGET', runKey, 'status')
if (kind == 'step' and status ~= runningStatus) or
   (kind == 'compensation' and status ~= failedStatus) then return 0 end
if redis.call('HGET', runKey, 'execution_id') ~= executionId then return 0 end
local raw = redis.call('HGET', journalKey, name)
local currentRevision = 0
if raw then currentRevision = tonumber(cjson.decode(raw)['revision']) or 0 end
if currentRevision ~= expected or newRevision ~= expected + 1 then return 0 end
if kind == 'compensation' and not raw then return 0 end
local record = cjson.decode(data)
if kind == 'compensation' and raw then
  record['position'] = cjson.decode(raw)['position']
end
redis.call('HSET', journalKey, name, cjson.encode(record))
if kind == 'step' and hasCheckpoint then
  writeCheckpoint(KEYS[6], KEYS[7], name, checkpointValue)
end
if kind == 'step' and hasCompensation then
  if not redis.call('HGET', compensationKey, name) then
    local position = redis.call('INCR', compensationSequenceKey)
    local compensation = cjson.decode(ARGV[12])
    compensation['position'] = position
    redis.call('HSET', compensationKey, name, cjson.encode(compensation))
    redis.call('ZADD', compensationOrderKey, position, name)
  end
end
redis.call('HSET', runKey, 'updated_at', ARGV[13])
return 1
''';

  static const _luaRewindJournal = '''
local names = redis.call('ZRANGE', KEYS[3], 0, -1)
local indices = {}
local nextIndex = 0
for _, name in ipairs(names) do
  local hash = string.find(name, '#', 1, true)
  local base = hash and string.sub(name, 1, hash - 1) or name
  if indices[base] == nil then
    indices[base] = nextIndex
    nextIndex = nextIndex + 1
  end
end
local target = indices[ARGV[1]]
if target == nil then return 0 end
local keep = {}
for _, name in ipairs(names) do
  local hash = string.find(name, '#', 1, true)
  local base = hash and string.sub(name, 1, hash - 1) or name
  if indices[base] < target then
    keep[name] = true
  else
    redis.call('HDEL', KEYS[2], name)
    redis.call('ZREM', KEYS[3], name)
  end
end
for _, journalKey in ipairs({KEYS[4], KEYS[5]}) do
  for _, name in ipairs(redis.call('HKEYS', journalKey)) do
    if not keep[name] then
      redis.call('HDEL', journalKey, name)
      redis.call('ZREM', KEYS[6], name)
    end
  end
end
local watcher = redis.call('HGET', KEYS[7], ARGV[2])
if watcher then
  local parsed = cjson.decode(watcher)
  redis.call('HDEL', KEYS[7], ARGV[2])
  if parsed['watchersTopicKey'] then redis.call('ZREM', parsed['watchersTopicKey'], ARGV[2]) end
  if parsed['topicSetKey'] then redis.call('SREM', parsed['topicSetKey'], ARGV[2]) end
end
redis.call('ZREM', KEYS[8], ARGV[2])
redis.call('HSET', KEYS[1], 'status', ARGV[3], 'wait_topic', '',
  'resume_at', '', 'owner_id', '', 'lease_expires_at', '',
  'execution_id', '', 'suspension_data', ARGV[4])
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
local executionId = redis.call('HGET', runKey, 'execution_id')
if executionId and executionId ~= '' and lease and lease ~= '' and tonumber(lease) > nowMs then
  return 0
end
if currentOwner and currentOwner ~= '' and currentOwner ~= ownerId then
  if lease and lease ~= '' and tonumber(lease) > nowMs then
    return 0
  end
end

redis.call('HSET', runKey,
  'owner_id', ownerId,
  'lease_expires_at', tostring(nowMs + leaseMs),
  'execution_id', '',
  'updated_at', nowIso)
return 1
''';

  static const _luaClaimRunExecution = '''
local runKey = KEYS[1]
local nowMs = tonumber(ARGV[1])
local ownerId = ARGV[2]
local leaseMs = tonumber(ARGV[3])
local runningStatus = ARGV[4]
local nowIso = ARGV[5]
local executionId = ARGV[6]
local status = redis.call('HGET', runKey, 'status')
if not status or status ~= runningStatus then return 0 end
local waitTopic = redis.call('HGET', runKey, 'wait_topic')
if waitTopic and waitTopic ~= '' then return 0 end
local owner = redis.call('HGET', runKey, 'owner_id')
local lease = redis.call('HGET', runKey, 'lease_expires_at')
if owner and owner ~= '' and lease and lease ~= '' and tonumber(lease) > nowMs then return 0 end
local expires = nowMs + leaseMs
redis.call('HSET', runKey, 'owner_id', ownerId, 'lease_expires_at', tostring(expires),
  'execution_id', executionId, 'updated_at', nowIso)
return {executionId, tostring(expires)}
''';

  static const _luaRenewRunExecution = '''
local runKey = KEYS[1]
local nowMs = tonumber(ARGV[1])
local leaseMs = tonumber(ARGV[2])
local runningStatus = ARGV[3]
local nowIso = ARGV[4]
local executionId = ARGV[5]
if redis.call('HGET', runKey, 'status') ~= runningStatus then return 0 end
if redis.call('HGET', runKey, 'execution_id') ~= executionId then return 0 end
local lease = redis.call('HGET', runKey, 'lease_expires_at')
if not lease or lease == '' or tonumber(lease) <= nowMs then return 0 end
redis.call('HSET', runKey, 'lease_expires_at', tostring(nowMs + leaseMs), 'updated_at', nowIso)
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
local executionId = redis.call('HGET', runKey, 'execution_id')
if executionId and executionId ~= '' then
  return 0
end
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
local executionId = redis.call('HGET', runKey, 'execution_id')
if executionId and executionId ~= '' then
  return 0
end
if not currentOwner or currentOwner ~= ownerId then
  return 0
end

redis.call('HSET', runKey,
  'owner_id', '',
  'lease_expires_at', '',
  'updated_at', nowIso)
return 1
''';

  static const _luaReleaseRunExecution = '''
local runKey = KEYS[1]
if redis.call('HGET', runKey, 'execution_id') ~= ARGV[1] then return 0 end
redis.call('HSET', runKey, 'owner_id', '', 'lease_expires_at', '', 'updated_at', ARGV[2])
return 1
''';

  static const _luaMarkFailedForExecution = '''
local runKey = KEYS[1]
local watchersHash = KEYS[2]
local dueKey = KEYS[3]
local executionId = ARGV[1]
local failedStatus = ARGV[2]
local status = redis.call('HGET', runKey, 'status')
if redis.call('HGET', runKey, 'execution_id') ~= executionId then return 2 end
if status == failedStatus then return 1 end
if status == ARGV[3] or status == ARGV[4] then return 2 end
if ARGV[8] == '0' then
  redis.call('HSET', runKey, 'last_error', ARGV[6], 'updated_at', ARGV[7])
  return 0
end
local runId = ARGV[5]
local watcher = redis.call('HGET', watchersHash, runId)
if watcher then
  local parsed = cjson.decode(watcher)
  redis.call('HDEL', watchersHash, runId)
  if parsed['watchersTopicKey'] then redis.call('ZREM', parsed['watchersTopicKey'], runId) end
  if parsed['topicSetKey'] then redis.call('SREM', parsed['topicSetKey'], runId) end
end
redis.call('ZREM', dueKey, runId)
redis.call('HSET', runKey, 'status', failedStatus, 'last_error', ARGV[6],
  'owner_id', '', 'lease_expires_at', '', 'resume_at', '', 'wait_topic', '',
  'updated_at', ARGV[7])
return 0
''';

  static const _luaCompleteIfActive = '''
local runKey = KEYS[1]
local watchersHash = KEYS[2]
local dueKey = KEYS[3]
local runId = ARGV[1]
local runningStatus = ARGV[2]
local suspendedStatus = ARGV[3]
local terminalStatus = ARGV[4]
local status = redis.call('HGET', runKey, 'status')
if status ~= runningStatus and status ~= suspendedStatus then return 0 end
local waitTopic = redis.call('HGET', runKey, 'wait_topic')
local watcher = redis.call('HGET', watchersHash, runId)
if watcher then
  local parsed = cjson.decode(watcher)
  redis.call('HDEL', watchersHash, runId)
  if parsed['watchersTopicKey'] then redis.call('ZREM', parsed['watchersTopicKey'], runId) end
  if parsed['topicSetKey'] then redis.call('SREM', parsed['topicSetKey'], runId) end
end
redis.call('ZREM', dueKey, runId)
if waitTopic and waitTopic ~= '' then
  local prefix = string.match(runKey, '^(.*:wf:)')
  redis.call('SREM', prefix .. 'topic:' .. waitTopic, runId)
end
redis.call('HSET', runKey, 'status', terminalStatus, 'result', ARGV[5],
  'suspension_data', '', 'wait_topic', '', 'resume_at', '',
  'owner_id', '', 'lease_expires_at', '', 'updated_at', ARGV[6])
return 1
''';

  static const _luaCancelIfActive = '''
local runKey = KEYS[1]
local watchersHash = KEYS[2]
local dueKey = KEYS[3]
local runId = ARGV[1]
local runningStatus = ARGV[2]
local suspendedStatus = ARGV[3]
local terminalStatus = ARGV[4]
local status = redis.call('HGET', runKey, 'status')
if status ~= runningStatus and status ~= suspendedStatus then return 0 end
local waitTopic = redis.call('HGET', runKey, 'wait_topic')
local watcher = redis.call('HGET', watchersHash, runId)
if watcher then
  local parsed = cjson.decode(watcher)
  redis.call('HDEL', watchersHash, runId)
  if parsed['watchersTopicKey'] then redis.call('ZREM', parsed['watchersTopicKey'], runId) end
  if parsed['topicSetKey'] then redis.call('SREM', parsed['topicSetKey'], runId) end
end
redis.call('ZREM', dueKey, runId)
if waitTopic and waitTopic ~= '' then
  local prefix = string.match(runKey, '^(.*:wf:)')
  redis.call('SREM', prefix .. 'topic:' .. waitTopic, runId)
end
redis.call('HSET', runKey, 'status', terminalStatus, 'cancellation_data', ARGV[5],
  'suspension_data', '', 'wait_topic', '', 'resume_at', '',
  'owner_id', '', 'lease_expires_at', '', 'execution_id', '',
  'updated_at', ARGV[6])
return 1
''';

  static const _luaMarkRunning = '''
local runKey = KEYS[1]
local watchersHash = KEYS[2]
local dueKey = KEYS[3]
local runId = ARGV[1]
local status = redis.call('HGET', runKey, 'status')
if status ~= ARGV[2] and status ~= ARGV[3] then return 0 end
local waitTopic = redis.call('HGET', runKey, 'wait_topic')
local watcher = redis.call('HGET', watchersHash, runId)
if watcher then
  local parsed = cjson.decode(watcher)
  redis.call('HDEL', watchersHash, runId)
  if parsed['watchersTopicKey'] then redis.call('ZREM', parsed['watchersTopicKey'], runId) end
  if parsed['topicSetKey'] then redis.call('SREM', parsed['topicSetKey'], runId) end
end
redis.call('ZREM', dueKey, runId)
if waitTopic and waitTopic ~= '' then
  local prefix = string.match(runKey, '^(.*:wf:)')
  redis.call('SREM', prefix .. 'topic:' .. waitTopic, runId)
end
redis.call('HSET', runKey, 'status', ARGV[4], 'resume_at', '', 'wait_topic', '', 'updated_at', ARGV[5])
return 1
''';

  static const _luaMarkResumed = '''
local runKey = KEYS[1]
local watchersHash = KEYS[2]
local dueKey = KEYS[3]
local runId = ARGV[1]
local status = redis.call('HGET', runKey, 'status')
if status ~= ARGV[2] and status ~= ARGV[3] then return 0 end
local waitTopic = redis.call('HGET', runKey, 'wait_topic')
local watcher = redis.call('HGET', watchersHash, runId)
if watcher then
  local parsed = cjson.decode(watcher)
  redis.call('HDEL', watchersHash, runId)
  if parsed['watchersTopicKey'] then redis.call('ZREM', parsed['watchersTopicKey'], runId) end
  if parsed['topicSetKey'] then redis.call('SREM', parsed['topicSetKey'], runId) end
end
redis.call('ZREM', dueKey, runId)
if waitTopic and waitTopic ~= '' then
  local prefix = string.match(runKey, '^(.*:wf:)')
  redis.call('SREM', prefix .. 'topic:' .. waitTopic, runId)
end
redis.call('HSET', runKey, 'status', ARGV[4], 'wait_topic', '', 'resume_at', '',
  'suspension_data', ARGV[5], 'execution_id', '', 'owner_id', '',
  'lease_expires_at', '', 'updated_at', ARGV[6])
return 1
''';

  static const _luaSuspend = '''
local runKey = KEYS[1]
local dueKey = KEYS[2]
local topicSetKey = KEYS[3]
local status = redis.call('HGET', runKey, 'status')
if status ~= ARGV[1] and status ~= ARGV[2] then return 0 end
redis.call('HSET', runKey, 'status', ARGV[3], 'wait_topic', ARGV[4],
  'resume_at', ARGV[5], 'suspension_data', ARGV[6], 'updated_at', ARGV[7])
if ARGV[5] ~= '' then
  redis.call('ZADD', dueKey, ARGV[5], ARGV[8])
else
  redis.call('ZREM', dueKey, ARGV[8])
end
if ARGV[4] ~= '' then redis.call('SADD', topicSetKey, ARGV[8]) end
return 1
''';

  static const _luaMarkFailed = '''
local runKey = KEYS[1]
local watchersHash = KEYS[2]
local dueKey = KEYS[3]
local status = redis.call('HGET', runKey, 'status')
if not status then return 0 end
if ARGV[4] ~= '1' then
  redis.call('HSET', runKey, 'last_error', ARGV[5], 'updated_at', ARGV[6])
  return 1
end
if status ~= ARGV[1] and status ~= ARGV[2] then return 0 end
local watcher = redis.call('HGET', watchersHash, ARGV[7])
if watcher then
  local parsed = cjson.decode(watcher)
  redis.call('HDEL', watchersHash, ARGV[7])
  if parsed['watchersTopicKey'] then redis.call('ZREM', parsed['watchersTopicKey'], ARGV[7]) end
  if parsed['topicSetKey'] then redis.call('SREM', parsed['topicSetKey'], ARGV[7]) end
end
redis.call('ZREM', dueKey, ARGV[7])
redis.call('HSET', runKey, 'status', ARGV[3], 'last_error', ARGV[5],
  'owner_id', '', 'lease_expires_at', '', 'resume_at', '', 'wait_topic', '',
  'updated_at', ARGV[6])
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
    String? runId,
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) async {
    final now = _clock.now();
    final nowIso = now.toIso8601String();
    final id = (runId != null && runId.trim().isNotEmpty)
        ? runId.trim()
        : 'wf-${now.microsecondsSinceEpoch}-${_idCounter++}';
    final result = await _send([
      'EVAL',
      _luaCreateRun,
      '3',
      _runKey(id),
      _stepsKey(id),
      _orderKey(id),
      workflow,
      WorkflowStatus.running.name,
      jsonEncode(params),
      nowIso,
      nowIso,
      '',
      '',
      if (cancellationPolicy != null && !cancellationPolicy.isEmpty)
        jsonEncode(cancellationPolicy.toJson())
      else
        '',
    ]);
    if (result != 1 && result != '1') {
      throw StateError('Workflow run "$id" already exists.');
    }
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
      executionId: _normalizeString(map['execution_id']),
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
    await _send([
      'EVAL',
      _luaSaveStep,
      '3',
      _runKey(runId),
      _stepsKey(runId),
      _orderKey(runId),
      stepName,
      jsonEncode(value),
      nowIso,
    ]);
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
      'EVAL',
      _luaSuspend,
      '3',
      _runKey(runId),
      _dueKey(),
      _topicKey(''),
      WorkflowStatus.running.name,
      WorkflowStatus.suspended.name,
      WorkflowStatus.suspended.name,
      '',
      when.millisecondsSinceEpoch.toString(),
      jsonEncode(metadata),
      now,
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
      'EVAL',
      _luaSuspend,
      '3',
      _runKey(runId),
      _dueKey(),
      _topicKey(topic),
      WorkflowStatus.running.name,
      WorkflowStatus.suspended.name,
      WorkflowStatus.suspended.name,
      topic,
      deadline?.millisecondsSinceEpoch.toString() ?? '',
      jsonEncode(metadata),
      now,
      runId,
    ]);
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
      WorkflowStatus.running.name,
      WorkflowStatus.suspended.name,
    ]);
  }

  @override
  Future<void> markRunning(String runId, {String? stepName}) async {
    final now = _clock.now().toIso8601String();
    await _send([
      'EVAL',
      _luaMarkRunning,
      '3',
      _runKey(runId),
      _watchersHashKey(),
      _dueKey(),
      runId,
      WorkflowStatus.running.name,
      WorkflowStatus.suspended.name,
      WorkflowStatus.running.name,
      now,
    ]);
  }

  @override
  Future<void> markCompleted(String runId, Object? result) async {
    await completeIfActive(runId, result);
  }

  @override
  Future<bool> completeIfActive(String runId, Object? result) async {
    final now = _clock.now().toIso8601String();
    final response = await _send([
      'EVAL',
      _luaCompleteIfActive,
      '3',
      _runKey(runId),
      _watchersHashKey(),
      _dueKey(),
      runId,
      WorkflowStatus.running.name,
      WorkflowStatus.suspended.name,
      WorkflowStatus.completed.name,
      jsonEncode(result),
      now,
    ]);
    return response == 1 || response == '1';
  }

  @override
  Future<void> markFailed(
    String runId,
    Object error,
    StackTrace stack, {
    bool terminal = false,
  }) async {
    final now = _clock.now().toIso8601String();
    await _send([
      'EVAL',
      _luaMarkFailed,
      '3',
      _runKey(runId),
      _watchersHashKey(),
      _dueKey(),
      WorkflowStatus.running.name,
      WorkflowStatus.suspended.name,
      WorkflowStatus.failed.name,
      if (terminal) '1' else '0',
      jsonEncode({'error': error.toString(), 'stack': stack.toString()}),
      now,
      runId,
    ]);
  }

  @override
  Future<void> markResumed(String runId, {Map<String, Object?>? data}) async {
    final now = _clock.now().toIso8601String();
    await _send([
      'EVAL',
      _luaMarkResumed,
      '3',
      _runKey(runId),
      _watchersHashKey(),
      _dueKey(),
      runId,
      WorkflowStatus.running.name,
      WorkflowStatus.suspended.name,
      WorkflowStatus.running.name,
      jsonEncode(data),
      now,
    ]);
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

  /// Claims a runnable run with a unique execution token.
  @override
  Future<WorkflowExecutionClaim?> claimRunExecution(
    String runId, {
    required String ownerId,
    Duration leaseDuration = const Duration(seconds: 30),
  }) async {
    final now = _clock.now();
    final executionId = const Uuid().v7();
    final raw = await _send([
      'EVAL',
      _luaClaimRunExecution,
      '1',
      _runKey(runId),
      now.millisecondsSinceEpoch.toString(),
      ownerId,
      leaseDuration.inMilliseconds.toString(),
      WorkflowStatus.running.name,
      now.toIso8601String(),
      executionId,
    ]);
    if (raw is! List || raw.length < 2) return null;
    final expiresMs = int.tryParse(raw[1].toString());
    if (expiresMs == null) return null;
    return WorkflowExecutionClaim(
      runId: runId,
      executionId: executionId,
      ownerId: ownerId,
      leaseExpiresAt: DateTime.fromMillisecondsSinceEpoch(
        expiresMs,
        isUtc: true,
      ),
    );
  }

  /// Renews the lease for the execution identified by [executionId].
  @override
  Future<bool> renewRunExecution(
    String runId, {
    required String executionId,
    Duration leaseDuration = const Duration(seconds: 30),
  }) async {
    final now = _clock.now();
    final result = await _send([
      'EVAL',
      _luaRenewRunExecution,
      '1',
      _runKey(runId),
      now.millisecondsSinceEpoch.toString(),
      leaseDuration.inMilliseconds.toString(),
      WorkflowStatus.running.name,
      now.toIso8601String(),
      executionId,
    ]);
    return result == 1 || result == '1';
  }

  /// Releases the lease for [executionId], without changing its token.
  @override
  Future<void> releaseRunExecution(
    String runId, {
    required String executionId,
  }) async {
    await _send([
      'EVAL',
      _luaReleaseRunExecution,
      '1',
      _runKey(runId),
      executionId,
      _clock.now().toIso8601String(),
    ]);
  }

  /// Atomically records a terminal failure for the current execution.
  @override
  Future<TerminalFailureResult> markFailedForExecution(
    String runId, {
    required String executionId,
    required Object error,
    required StackTrace stack,
    bool terminal = true,
  }) async {
    final result = await _send([
      'EVAL',
      _luaMarkFailedForExecution,
      '3',
      _runKey(runId),
      _watchersHashKey(),
      _dueKey(),
      executionId,
      WorkflowStatus.failed.name,
      WorkflowStatus.completed.name,
      WorkflowStatus.cancelled.name,
      runId,
      jsonEncode({'error': error.toString(), 'stack': stack.toString()}),
      _clock.now().toIso8601String(),
      if (terminal) '1' else '0',
    ]);
    final code = result is int ? result : int.tryParse(result.toString());
    return switch (code) {
      0 => TerminalFailureResult.applied,
      1 => TerminalFailureResult.alreadyFailedForExecution,
      _ => TerminalFailureResult.superseded,
    };
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
              WorkflowStatus.suspended.name,
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
    await cancelIfActive(runId, reason: reason);
  }

  @override
  Future<bool> cancelIfActive(String runId, {String? reason}) async {
    final now = _clock.now();
    final cancellationData = <String, Object?>{
      'reason': reason ?? 'cancelled',
      'cancelledAt': now.toIso8601String(),
    };
    final response = await _send([
      'EVAL',
      _luaCancelIfActive,
      '3',
      _runKey(runId),
      _watchersHashKey(),
      _dueKey(),
      runId,
      WorkflowStatus.running.name,
      WorkflowStatus.suspended.name,
      WorkflowStatus.cancelled.name,
      jsonEncode(cancellationData),
      now.toIso8601String(),
    ]);
    return response == 1 || response == '1';
  }

  @override
  Future<WorkflowJournalSnapshot?> readJournal(
    String runId,
    WorkflowJournalKind kind,
    String name,
  ) async {
    final run = await get(runId);
    if (run == null) return null;
    final raw = await _send(['HGET', _journalKey(runId, kind), name]);
    return WorkflowJournalSnapshot(
      run: run,
      entry: raw == null ? null : _journalEntry(_decode(raw as String)),
    );
  }

  @override
  Future<List<WorkflowJournalEntry>> listCompensations(String runId) async {
    final names =
        await _send(['ZREVRANGE', _compensationOrderKey(runId), '0', '-1'])
            as List? ??
        const [];
    final entries = <WorkflowJournalEntry>[];
    for (final name in names.cast<String>()) {
      final raw = await _send([
        'HGET',
        _journalKey(runId, WorkflowJournalKind.compensation),
        name,
      ]);
      if (raw != null) entries.add(_journalEntry(_decode(raw as String)));
    }
    return entries;
  }

  @override
  Future<bool> commitJournal(
    WorkflowJournalEntry entry, {
    required int expectedRevision,
    required String executionId,
    WorkflowJournalCheckpoint? checkpoint,
  }) async {
    if (entry.revision != expectedRevision + 1 || expectedRevision < 0) {
      return false;
    }
    if (checkpoint != null && entry.kind != WorkflowJournalKind.step) {
      return false;
    }
    final compensation = checkpoint?.compensation;
    final response = await _send([
      'EVAL',
      _luaCommitJournal,
      '7',
      _runKey(entry.runId),
      _journalKey(entry.runId, entry.kind),
      _journalKey(entry.runId, WorkflowJournalKind.compensation),
      _compensationOrderKey(entry.runId),
      _compensationSequenceKey(entry.runId),
      _stepsKey(entry.runId),
      _orderKey(entry.runId),
      entry.kind.name,
      entry.name,
      expectedRevision.toString(),
      entry.revision.toString(),
      executionId,
      jsonEncode({
        'runId': entry.runId,
        'kind': entry.kind.name,
        'name': entry.name,
        'revision': entry.revision,
        'data': entry.data,
        'position': entry.position,
      }),
      if (checkpoint == null) '' else jsonEncode(checkpoint.value),
      if (checkpoint == null) '0' else '1',
      if (compensation == null) '0' else '1',
      WorkflowStatus.running.name,
      WorkflowStatus.failed.name,
      if (compensation == null)
        ''
      else
        jsonEncode({
          'runId': entry.runId,
          'kind': WorkflowJournalKind.compensation.name,
          'name': entry.name,
          'revision': 1,
          'data': compensation.toJournalData(),
          'position': null,
        }),
      _clock.now().toUtc().toIso8601String(),
    ]);
    return response == 1 || response == '1';
  }

  @override
  Future<void> rewindToStep(String runId, String stepName) async {
    await _send([
      'EVAL',
      _luaRewindJournal,
      '8',
      _runKey(runId),
      _stepsKey(runId),
      _orderKey(runId),
      _journalKey(runId, WorkflowJournalKind.step),
      _journalKey(runId, WorkflowJournalKind.compensation),
      _compensationOrderKey(runId),
      _watchersHashKey(),
      _dueKey(),
      stepName,
      runId,
      WorkflowStatus.suspended.name,
      jsonEncode({
        'step': stepName,
        'iteration': 0,
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

  Map<String, Object?> _decodeMap(String? value) {
    if (value == null || value.isEmpty) return const {};
    final decoded = jsonDecode(value);
    return decoded is Map ? decoded.cast<String, Object?>() : const {};
  }

  Object? _decode(String? value) {
    if (value == null || value.isEmpty) return null;
    return jsonDecode(value);
  }

  WorkflowJournalEntry _journalEntry(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid workflow journal record.');
    }
    final map = value.cast<String, Object?>();
    final kind = WorkflowJournalKind.values.firstWhere(
      (candidate) => candidate.name == map['kind'],
      orElse: () => throw const FormatException('Invalid journal kind.'),
    );
    final data = map['data'];
    if (map['runId'] is! String ||
        map['name'] is! String ||
        map['revision'] is! int ||
        data is! Map) {
      throw const FormatException('Invalid workflow journal record.');
    }
    return WorkflowJournalEntry(
      runId: map['runId']! as String,
      kind: kind,
      name: map['name']! as String,
      revision: map['revision']! as int,
      data: data.cast<String, Object?>(),
      position: map['position'] as int?,
    );
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
