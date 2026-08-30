/// Portable task invocation context for event-driven and JS runtimes.
library;

import 'dart:async';

import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/workflow/core/workflow_event_ref.dart';
import 'package:stem/src/workflow/core/workflow_ref.dart';

/// Signature for task entrypoints.
typedef TaskEntrypoint =
    FutureOr<Object?> Function(
      TaskInvocationContext context,
      Map<String, Object?> args,
    );

/// Context exposed to task entrypoints in a portable runtime.
///
/// Runtime capabilities are supplied as callbacks and narrow interfaces. No
/// isolate transport is required or exposed by this implementation.
class TaskInvocationContext extends TaskContext {
  /// Creates a context for execution in the current runtime.
  factory TaskInvocationContext.local({
    required String id,
    required Map<String, String> headers,
    required Map<String, Object?> meta,
    required int attempt,
    required void Function() heartbeat,
    required Future<void> Function(Duration) extendLease,
    required Future<void> Function(
      double percent, {
      Map<String, Object?>? data,
    })
    progress,
    TaskCancellationToken cancellation = const TaskCancellationToken.none(),
    Map<String, Object?> args = const {},
    TaskEnqueuer? enqueuer,
    WorkflowCaller? workflows,
    WorkflowEventEmitter? workflowEvents,
  }) => TaskInvocationContext._(
    id: id,
    args: args,
    headers: headers,
    meta: meta,
    attempt: attempt,
    heartbeat: heartbeat,
    extendLease: extendLease,
    progress: progress,
    cancellation: cancellation,
    enqueuer: enqueuer,
    workflows: workflows,
    workflowEvents: workflowEvents,
  );

  TaskInvocationContext._({
    required super.id,
    required super.args,
    required super.headers,
    required super.meta,
    required super.attempt,
    required super.heartbeat,
    required super.extendLease,
    required super.progress,
    required super.cancellation,
    super.enqueuer,
    super.workflows,
    super.workflowEvents,
  });
}
