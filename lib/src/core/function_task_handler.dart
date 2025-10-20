import 'dart:async';

import 'contracts.dart';
import 'task_invocation.dart';

/// Convenience task handler that delegates execution to a top-level function
/// suitable for isolate execution.
class FunctionTaskHandler<R> implements TaskHandler<R> {
  FunctionTaskHandler({
    required this.name,
    required TaskEntrypoint entrypoint,
    this.options = const TaskOptions(),
  }) : _entrypoint = entrypoint;

  @override
  final String name;

  @override
  final TaskOptions options;

  final TaskEntrypoint _entrypoint;

  @override
  TaskEntrypoint get isolateEntrypoint => _entrypoint;

  @override
  Future<R> call(TaskContext context, Map<String, Object?> args) async {
    final invocationContext = TaskInvocationContext.local(
      headers: context.headers,
      meta: context.meta,
      attempt: context.attempt,
      heartbeat: context.heartbeat,
      extendLease: context.extendLease,
      progress: (percent, {data}) => context.progress(percent, data: data),
    );
    final result = await _entrypoint(invocationContext, args);
    return result as R;
  }
}
