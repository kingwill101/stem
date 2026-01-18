/// Task invocation abstraction and execution context.
///
/// This library defines the [TaskInvocationContext], which is the primary
/// interface exposed to task handlers during execution. It abstracts away
/// the differences between local (same isolate) and remote (pool isolate)
/// execution.
///
/// ## Context Types
///
/// Tasks can be invoked in two main environments:
///
/// 1. **Local**: Used for in-process execution or testing. Communication
///    with the framework happens via direct function calls.
/// 2. **Remote**: Used by the `TaskIsolatePool`. Communication happens via
///    `Isolate` ports using [TaskInvocationSignal]s.
///
/// ## Core Capabilities
///
/// - **Heartbeats**: Notify the worker that the task is still healthy.
/// - **Lease Extension**: Request more time for long-running tasks.
/// - **Progress Reporting**: Send telemetry back for monitoring.
/// - **Sub-task Spawning**: Enqueue new tasks with automatic lineage tracking.
/// - **Retry Control**: Declaratively request retries with policy overrides.
///
/// ## Message Protocol
///
/// When running in an isolate, the context uses [TaskInvocationSignal] and
/// its subclasses ([HeartbeatSignal], [ProgressSignal], etc.) to communicate
/// with the `Worker` or `TaskIsolatePool`.
///
/// See also:
/// - `Worker` for the runtime that provides this context.
/// - `TaskIsolatePool` for the isolate management layer.
library;

import 'dart:async';
import 'dart:isolate';

import 'package:stem/src/core/contracts.dart';

/// Signature for task entrypoints that can run inside isolate executors.
typedef TaskEntrypoint =
    FutureOr<Object?> Function(
      TaskInvocationContext context,
      Map<String, Object?> args,
    );

/// Control messages emitted by task entrypoints running inside isolates.
sealed class TaskInvocationSignal {
  const TaskInvocationSignal();
}

/// Signals a heartbeat from an executing task.
class HeartbeatSignal extends TaskInvocationSignal {
  /// Creates a heartbeat signal.
  const HeartbeatSignal();
}

/// Signals a request to extend a task lease.
class ExtendLeaseSignal extends TaskInvocationSignal {
  /// Creates a lease extension signal.
  const ExtendLeaseSignal(this.by);

  /// Duration to extend the lease by.
  final Duration by;
}

/// Signals a task progress update.
class ProgressSignal extends TaskInvocationSignal {
  /// Creates a progress signal with optional metadata.
  const ProgressSignal(this.percentComplete, {this.data});

  /// Completion percentage (0-100).
  final double percentComplete;

  /// Optional progress metadata.
  final Map<String, Object?>? data;
}

/// Request to enqueue a task from an isolate.
class EnqueueTaskSignal extends TaskInvocationSignal {
  /// Creates an enqueue request signal.
  const EnqueueTaskSignal(this.request, this.replyPort);

  /// Enqueue request payload.
  final TaskEnqueueRequest request;

  /// Port to deliver the response.
  final SendPort replyPort;
}

/// Enqueue request payload for isolate communication.
class TaskEnqueueRequest {
  /// Creates an enqueue request payload.
  const TaskEnqueueRequest({
    required this.name,
    required this.args,
    required this.headers,
    required this.options,
    required this.meta,
    this.enqueueOptions,
  });

  /// Task name to enqueue.
  final String name;

  /// Task arguments.
  final Map<String, Object?> args;

  /// Task headers.
  final Map<String, String> headers;

  /// Task options.
  final Map<String, Object?> options;

  /// Task metadata.
  final Map<String, Object?> meta;

  /// Enqueue options.
  final Map<String, Object?>? enqueueOptions;
}

/// Response payload for isolate enqueue requests.
class TaskEnqueueResponse {
  /// Creates a response payload.
  const TaskEnqueueResponse({this.taskId, this.error});

  /// Enqueued task id on success.
  final String? taskId;

  /// Error message when enqueue fails.
  final String? error;
}

/// Context exposed to task entrypoints regardless of execution environment.
class TaskInvocationContext implements TaskEnqueuer {
  /// Context implementation used when executing locally in the same isolate.
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
    TaskEnqueuer? enqueuer,
  }) => TaskInvocationContext._(
    id: id,
    headers: headers,
    meta: meta,
    attempt: attempt,
    heartbeat: heartbeat,
    extendLease: extendLease,
    progress: progress,
    enqueuer: enqueuer,
  );

  /// Context implementation used when executing inside a worker isolate.
  factory TaskInvocationContext.remote({
    required String id,
    required SendPort controlPort,
    required Map<String, String> headers,
    required Map<String, Object?> meta,
    required int attempt,
  }) => TaskInvocationContext._(
    id: id,
    headers: headers,
    meta: meta,
    attempt: attempt,
    heartbeat: () => controlPort.send(const HeartbeatSignal()),
    extendLease: (by) async => controlPort.send(ExtendLeaseSignal(by)),
    progress: (percent, {data}) async =>
        controlPort.send(ProgressSignal(percent, data: data)),
    enqueuer: _RemoteTaskEnqueuer(controlPort),
  );
  TaskInvocationContext._({
    required this.id,
    required this.headers,
    required this.meta,
    required this.attempt,
    required void Function() heartbeat,
    required Future<void> Function(Duration) extendLease,
    required Future<void> Function(
      double percent, {
      Map<String, Object?>? data,
    })
    progress,
    TaskEnqueuer? enqueuer,
  }) : _heartbeat = heartbeat,
       _extendLease = extendLease,
       _progress = progress,
       _enqueuer = enqueuer;

  /// The unique identifier of the task.
  final String id;

  /// Headers passed to the task invocation.
  final Map<String, String> headers;

  /// Invocation metadata (e.g. trace, tenant).
  final Map<String, Object?> meta;

  /// Current attempt count.
  final int attempt;

  final void Function() _heartbeat;
  final Future<void> Function(Duration) _extendLease;
  final Future<void> Function(
    double percent, {
    Map<String, Object?>? data,
  })
  _progress;

  /// Optional delegate used to enqueue tasks from within the invocation.
  final TaskEnqueuer? _enqueuer;

  /// Notify the worker that the task is still running.
  void heartbeat() => _heartbeat();

  /// Request an extension of the underlying broker lease/visibility timeout.
  Future<void> extendLease(Duration by) => _extendLease(by);

  /// Report progress back to the worker.
  Future<void> progress(double percentComplete, {Map<String, Object?>? data}) =>
      _progress(percentComplete, data: data);

  /// Enqueue a task from within a task invocation.
  ///
  /// Headers and metadata from this context are merged into the enqueue
  /// request. Lineage is added to `meta` unless
  /// `enqueueOptions.addToParent` is `false`.
  @override
  Future<String> enqueue(
    String name, {
    Map<String, Object?> args = const {},
    Map<String, String> headers = const {},
    TaskOptions options = const TaskOptions(),
    Map<String, Object?> meta = const {},
    TaskEnqueueOptions? enqueueOptions,
  }) async {
    final delegate = _enqueuer;
    if (delegate == null) {
      throw StateError('TaskInvocationContext has no enqueuer configured');
    }

    final mergedHeaders = Map<String, String>.from(this.headers)
      ..addAll(headers);
    final scopeMeta = TaskEnqueueScope.currentMeta();
    final mergedMeta = <String, Object?>{
      if (scopeMeta != null) ...scopeMeta,
      ...this.meta,
      ...meta,
    };

    if (enqueueOptions?.addToParent ?? true) {
      mergedMeta['stem.parentTaskId'] = id;
      mergedMeta['stem.parentAttempt'] = attempt;
      mergedMeta.putIfAbsent('stem.rootTaskId', () => id);
    }

    return delegate.enqueue(
      name,
      args: args,
      headers: mergedHeaders,
      options: options,
      meta: mergedMeta,
      enqueueOptions: enqueueOptions,
    );
  }

  /// Enqueue a typed task call from within a task invocation.
  ///
  /// This merges headers/meta from the task call and applies lineage metadata
  /// unless `enqueueOptions.addToParent` is `false`.
  @override
  Future<String> enqueueCall<TArgs, TResult>(
    TaskCall<TArgs, TResult> call, {
    TaskEnqueueOptions? enqueueOptions,
  }) async {
    final delegate = _enqueuer;
    if (delegate == null) {
      throw StateError('TaskInvocationContext has no enqueuer configured');
    }
    final resolvedEnqueueOptions = enqueueOptions ?? call.enqueueOptions;
    final mergedHeaders = Map<String, String>.from(headers)
      ..addAll(call.headers);
    final scopeMeta = TaskEnqueueScope.currentMeta();
    final mergedMeta = <String, Object?>{
      if (scopeMeta != null) ...scopeMeta,
      ...meta,
      ...call.meta,
    };

    if (resolvedEnqueueOptions?.addToParent ?? true) {
      mergedMeta['stem.parentTaskId'] = id;
      mergedMeta['stem.parentAttempt'] = attempt;
      mergedMeta.putIfAbsent('stem.rootTaskId', () => id);
    }

    final mergedCall = call.copyWith(
      headers: Map.unmodifiable(mergedHeaders),
      meta: Map.unmodifiable(mergedMeta),
    );
    return delegate.enqueueCall(
      mergedCall,
      enqueueOptions: resolvedEnqueueOptions,
    );
  }

  /// Build a fluent enqueue request for this invocation.
  ///
  /// Use [TaskEnqueueBuilder.build] + [enqueueCall] to dispatch.
  TaskEnqueueBuilder<TArgs, TResult> enqueueBuilder<TArgs, TResult>({
    required TaskDefinition<TArgs, TResult> definition,
    required TArgs args,
  }) {
    return TaskEnqueueBuilder(definition: definition, args: args);
  }

  /// Alias for enqueue.
  Future<String> spawn(
    String name, {
    Map<String, Object?> args = const {},
    Map<String, String> headers = const {},
    TaskOptions options = const TaskOptions(),
    Map<String, Object?> meta = const {},
    TaskEnqueueOptions? enqueueOptions,
  }) {
    return enqueue(
      name,
      args: args,
      headers: headers,
      options: options,
      meta: meta,
      enqueueOptions: enqueueOptions,
    );
  }

  /// Request a retry of the current task invocation.
  ///
  /// Throws a [TaskRetryRequest] which is intercepted by the worker to
  /// schedule the retry. Override retry policies/time limits per invocation
  /// by passing the optional parameters.
  Future<void> retry({
    Duration? countdown,
    DateTime? eta,
    TaskRetryPolicy? retryPolicy,
    int? maxRetries,
    Duration? timeLimit,
    Duration? softTimeLimit,
  }) {
    throw TaskRetryRequest(
      countdown: countdown,
      eta: eta,
      retryPolicy: retryPolicy,
      maxRetries: maxRetries,
      timeLimit: timeLimit,
      softTimeLimit: softTimeLimit,
    );
  }
}

class _RemoteTaskEnqueuer implements TaskEnqueuer {
  /// Enqueuer that proxies enqueue requests over the isolate control port.
  _RemoteTaskEnqueuer(this._controlPort);

  /// Port to the worker isolate controller.
  final SendPort _controlPort;

  @override
  Future<String> enqueue(
    String name, {
    Map<String, Object?> args = const {},
    Map<String, String> headers = const {},
    TaskOptions options = const TaskOptions(),
    Map<String, Object?> meta = const {},
    TaskEnqueueOptions? enqueueOptions,
  }) async {
    /// Sends the enqueue request to the worker isolate and waits for a reply.
    final responsePort = ReceivePort();
    _controlPort.send(
      EnqueueTaskSignal(
        TaskEnqueueRequest(
          name: name,
          args: args,
          headers: headers,
          options: options.toJson(),
          meta: meta,
          enqueueOptions: enqueueOptions?.toJson(),
        ),
        responsePort.sendPort,
      ),
    );
    final response = await responsePort.first;
    responsePort.close();
    if (response is TaskEnqueueResponse) {
      if (response.error != null) {
        throw StateError(response.error!);
      }
      return response.taskId ?? '';
    }
    throw StateError('Unexpected enqueue response: $response');
  }

  @override
  Future<String> enqueueCall<TArgs, TResult>(
    TaskCall<TArgs, TResult> call, {
    TaskEnqueueOptions? enqueueOptions,
  }) {
    /// Enqueues a typed task call via the remote enqueue path.
    return enqueue(
      call.name,
      args: call.encodeArgs(),
      headers: call.headers,
      options: call.resolveOptions(),
      meta: call.meta,
      enqueueOptions: enqueueOptions ?? call.enqueueOptions,
    );
  }
}
