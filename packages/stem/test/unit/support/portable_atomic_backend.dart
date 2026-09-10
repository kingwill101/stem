// Copyright (c) 2025 Glenford Williams <hey@glenfordwilliams.com>
// SPDX-License-Identifier: MIT

import 'package:stem/memory.dart';
import 'package:stem/stem.dart';

/// Test backend advertising only the new atomic capability.
class PortableAtomicBackend
    implements ResultBackend, AtomicTerminalResultStore {
  final InMemoryResultBackend inner = InMemoryResultBackend();

  @override
  bool get supportsAtomicTerminalWrites => true;

  @override
  Future<bool> setTerminalIfAbsent(TaskStatus status, {Duration? ttl}) =>
      inner.setTerminalIfAbsent(status, ttl: ttl);

  @override
  Future<void> set(
    String taskId,
    TaskState state, {
    Object? payload,
    TaskError? error,
    int attempt = 0,
    Map<String, Object?> meta = const {},
    Duration? ttl,
  }) => inner.set(
    taskId,
    state,
    payload: payload,
    error: error,
    attempt: attempt,
    meta: meta,
    ttl: ttl,
  );

  @override
  Future<TaskStatus?> get(String taskId) => inner.get(taskId);

  @override
  Stream<TaskStatus> watch(String taskId) => inner.watch(taskId);

  @override
  Future<void> setWorkerHeartbeat(WorkerHeartbeat heartbeat) =>
      inner.setWorkerHeartbeat(heartbeat);

  @override
  Future<void> close() => inner.close();

  // Unsupported operations fail loudly if these focused tests start using them.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
