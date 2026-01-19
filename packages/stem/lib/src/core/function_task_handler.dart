import 'dart:async';

import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/task_invocation.dart';

/// Convenience task handler that delegates execution to a top-level function
/// suitable for isolate execution. Set [runInIsolate] to `false` or use
/// [FunctionTaskHandler.inline] to keep execution in the worker isolate.
class FunctionTaskHandler<R> implements TaskHandler<R> {
  /// Creates a task handler that delegates to a top-level [entrypoint].
  FunctionTaskHandler({
    required this.name,
    required TaskEntrypoint entrypoint,
    this.options = const TaskOptions(),
    this.metadata = const TaskMetadata(),
    this.runInIsolate = true,
  }) : _entrypoint = entrypoint;

  /// Creates a handler that always runs inline in the worker isolate.
  factory FunctionTaskHandler.inline({
    required String name,
    required TaskEntrypoint entrypoint,
    TaskOptions options = const TaskOptions(),
    TaskMetadata metadata = const TaskMetadata(),
  }) {
    return FunctionTaskHandler<R>(
      name: name,
      entrypoint: entrypoint,
      options: options,
      metadata: metadata,
      runInIsolate: false,
    );
  }

  @override
  final String name;

  @override
  final TaskOptions options;

  @override
  final TaskMetadata metadata;

  /// Whether the entrypoint should run in a worker isolate.
  final bool runInIsolate;

  final TaskEntrypoint _entrypoint;

  @override
  TaskEntrypoint? get isolateEntrypoint => runInIsolate ? _entrypoint : null;

  @override
  /// Invokes the entrypoint with a normalized invocation context.
  Future<R> call(TaskContext context, Map<String, Object?> args) async {
    final invocationContext = TaskInvocationContext.local(
      id: context.id,
      headers: context.headers,
      meta: context.meta,
      attempt: context.attempt,
      heartbeat: context.heartbeat,
      extendLease: context.extendLease,
      progress: (percent, {data}) => context.progress(percent, data: data),
      enqueuer: context.enqueuer,
    );
    final result = await _entrypoint(invocationContext, args);
    return result as R;
  }
}
