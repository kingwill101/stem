import 'dart:async';

import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/encoder_keys.dart';
import 'package:stem/src/core/task_payload_encoder.dart';
import 'package:stem/src/observability/heartbeat.dart';

/// Wraps a [ResultBackend] to encode/decode payloads via [registry].
ResultBackend withTaskPayloadEncoder(
  ResultBackend backend,
  TaskPayloadEncoderRegistry registry,
) {
  if (backend is EncodingResultBackend && backend.registry == registry) {
    return backend;
  }
  return EncodingResultBackend(backend, registry);
}

/// Result backend decorator that applies [TaskPayloadEncoder] semantics.
class EncodingResultBackend implements ResultBackend {
  /// Creates an encoding wrapper around the provided backend.
  EncodingResultBackend(this._inner, this.registry);

  final ResultBackend _inner;

  /// Encoder registry used to decode/encode stored payloads.
  final TaskPayloadEncoderRegistry registry;

  /// The wrapped backend used for persistence.
  ResultBackend get inner => _inner;

  @override
  Future<void> set(
    String taskId,
    TaskState state, {
    Object? payload,
    TaskError? error,
    int attempt = 0,
    Map<String, Object?> meta = const {},
    Duration? ttl,
  }) {
    final encoderId = meta[stemResultEncoderMetaKey] as String?;
    final encoder = registry.resolveResult(encoderId);
    final encodedPayload = encoder.encode(payload);
    return _inner.set(
      taskId,
      state,
      payload: encodedPayload,
      error: error,
      attempt: attempt,
      meta: meta,
      ttl: ttl,
    );
  }

  @override
  Future<TaskStatus?> get(String taskId) async {
    final status = await _inner.get(taskId);
    if (status == null) return null;
    return _decodeStatus(status);
  }

  @override
  Stream<TaskStatus> watch(String taskId) {
    return _inner.watch(taskId).map(_decodeStatus);
  }

  @override
  Future<void> setWorkerHeartbeat(WorkerHeartbeat heartbeat) =>
      _inner.setWorkerHeartbeat(heartbeat);

  @override
  Future<WorkerHeartbeat?> getWorkerHeartbeat(String workerId) =>
      _inner.getWorkerHeartbeat(workerId);

  @override
  Future<List<WorkerHeartbeat>> listWorkerHeartbeats() =>
      _inner.listWorkerHeartbeats();

  @override
  Future<void> initGroup(GroupDescriptor descriptor) =>
      _inner.initGroup(descriptor);

  @override
  Future<GroupStatus?> addGroupResult(String groupId, TaskStatus status) async {
    final encoded = _encodeStatus(status);
    final updated = await _inner.addGroupResult(groupId, encoded);
    return _decodeGroupStatus(updated);
  }

  @override
  Future<GroupStatus?> getGroup(String groupId) async {
    final status = await _inner.getGroup(groupId);
    return _decodeGroupStatus(status);
  }

  @override
  Future<void> expire(String taskId, Duration ttl) =>
      _inner.expire(taskId, ttl);

  @override
  Future<bool> claimChord(
    String groupId, {
    String? callbackTaskId,
    DateTime? dispatchedAt,
  }) => _inner.claimChord(
    groupId,
    callbackTaskId: callbackTaskId,
    dispatchedAt: dispatchedAt,
  );

  TaskStatus _encodeStatus(TaskStatus status) {
    final encoderId = status.meta[stemResultEncoderMetaKey] as String?;
    final encoder = registry.resolveResult(encoderId);
    final encodedPayload = encoder.encode(status.payload);
    if (identical(encodedPayload, status.payload)) {
      return status;
    }
    return TaskStatus(
      id: status.id,
      state: status.state,
      payload: encodedPayload,
      error: status.error,
      meta: status.meta,
      attempt: status.attempt,
    );
  }

  TaskStatus _decodeStatus(TaskStatus status) {
    final encoderId = status.meta[stemResultEncoderMetaKey] as String?;
    final encoder = registry.resolveResult(encoderId);
    final decodedPayload = encoder.decode(status.payload);
    if (identical(decodedPayload, status.payload)) {
      return status;
    }
    return TaskStatus(
      id: status.id,
      state: status.state,
      payload: decodedPayload,
      error: status.error,
      meta: status.meta,
      attempt: status.attempt,
    );
  }

  GroupStatus? _decodeGroupStatus(GroupStatus? status) {
    if (status == null) return null;
    if (status.results.isEmpty) return status;
    final decoded = <String, TaskStatus>{};
    var changed = false;
    status.results.forEach((key, value) {
      final decodedStatus = _decodeStatus(value);
      decoded[key] = decodedStatus;
      if (!identical(decodedStatus, value)) {
        changed = true;
      }
    });
    if (!changed) {
      return status;
    }
    return GroupStatus(
      id: status.id,
      expected: status.expected,
      results: decoded,
      meta: status.meta,
    );
  }
}
