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
import 'package:stem/src/core/payload_codec.dart';
import 'package:stem/src/core/payload_map.dart';
import 'package:stem/src/workflow/core/workflow_cancellation_policy.dart';
import 'package:stem/src/workflow/core/workflow_event_ref.dart';
import 'package:stem/src/workflow/core/workflow_ref.dart';
import 'package:stem/src/workflow/core/workflow_result.dart';

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

  /// Returns the decoded progress metadata value for [key], or `null`.
  T? dataValue<T>(String key, {PayloadCodec<T>? codec}) {
    final payload = data;
    if (payload == null) return null;
    return payload.value<T>(key, codec: codec);
  }

  /// Returns the decoded progress metadata value for [key], or [fallback].
  T dataValueOr<T>(String key, T fallback, {PayloadCodec<T>? codec}) {
    final payload = data;
    if (payload == null) return fallback;
    return payload.valueOr<T>(key, fallback, codec: codec);
  }

  /// Returns the decoded progress metadata value for [key], throwing if absent.
  T requiredDataValue<T>(String key, {PayloadCodec<T>? codec}) {
    final payload = data;
    if (payload == null) {
      throw StateError('Progress signal does not include metadata.');
    }
    return payload.requiredValue<T>(key, codec: codec);
  }

  /// Decodes the progress metadata value for [key] as a typed DTO with [codec].
  T? dataAs<T>(String key, {required PayloadCodec<T> codec}) {
    final payload = data;
    if (payload == null) return null;
    return payload.value<T>(key, codec: codec);
  }

  /// Decodes the full progress payload as a typed DTO with [codec].
  T? payloadAs<T>({required PayloadCodec<T> codec}) {
    final payload = data;
    if (payload == null) return null;
    return codec.decode(payload);
  }

  /// Decodes the progress metadata value for [key] as a typed DTO from JSON.
  T? dataJson<T>(
    String key, {
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    final payload = data;
    if (payload == null) return null;
    return payload.valueJson<T>(
      key,
      decode: decode,
      typeName: typeName,
    );
  }

  /// Decodes the full progress payload as a typed DTO from JSON.
  T? payloadJson<T>({
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    final payload = data;
    if (payload == null) return null;
    return PayloadCodec<T>.json(
      decode: decode,
      typeName: typeName,
    ).decode(payload);
  }

  /// Decodes the progress metadata value for [key] as a typed DTO from
  /// version-aware JSON.
  T? dataVersionedJson<T>(
    String key, {
    required int version,
    required T Function(Map<String, dynamic> payload, int version) decode,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    final payload = data;
    if (payload == null) return null;
    return payload.valueJson<T>(
      key,
      decode: (json) => PayloadCodec<T>.versionedJson(
        version: version,
        decode: decode,
        defaultDecodeVersion: defaultDecodeVersion,
        typeName: typeName,
      ).decode(json),
      typeName: typeName,
    );
  }

  /// Decodes the full progress payload as a typed DTO from version-aware JSON.
  T? payloadVersionedJson<T>({
    required int version,
    required T Function(Map<String, dynamic> payload, int version) decode,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    final payload = data;
    if (payload == null) return null;
    return PayloadCodec<T>.versionedJson(
      version: version,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: typeName,
    ).decode(payload);
  }
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

/// Request to start a workflow from an isolate.
class StartWorkflowSignal extends TaskInvocationSignal {
  /// Creates a workflow start request signal.
  const StartWorkflowSignal(this.request, this.replyPort);

  /// Workflow start request payload.
  final StartWorkflowRequest request;

  /// Port to deliver the response.
  final SendPort replyPort;
}

/// Request to wait for a workflow from an isolate.
class WaitForWorkflowSignal extends TaskInvocationSignal {
  /// Creates a workflow wait request signal.
  const WaitForWorkflowSignal(this.request, this.replyPort);

  /// Workflow wait request payload.
  final WaitForWorkflowRequest request;

  /// Port to deliver the response.
  final SendPort replyPort;
}

/// Request to emit a workflow event from an isolate.
class EmitWorkflowEventSignal extends TaskInvocationSignal {
  /// Creates a workflow event emit request signal.
  const EmitWorkflowEventSignal(this.request, this.replyPort);

  /// Workflow event emit request payload.
  final EmitWorkflowEventRequest request;

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
    this.notBefore,
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

  /// Optional delay before execution.
  final DateTime? notBefore;

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

/// Workflow start request payload for isolate communication.
class StartWorkflowRequest {
  /// Creates a workflow start request payload.
  const StartWorkflowRequest({
    required this.workflowName,
    required this.params,
    this.parentRunId,
    this.ttlMs,
    this.cancellationPolicy,
  });

  /// Workflow name to start.
  final String workflowName;

  /// Encoded workflow params.
  final Map<String, Object?> params;

  /// Optional parent workflow run id.
  final String? parentRunId;

  /// Optional run TTL in milliseconds.
  final int? ttlMs;

  /// Optional serialized cancellation policy.
  final Map<String, Object?>? cancellationPolicy;
}

/// Response payload for isolate workflow start requests.
class StartWorkflowResponse {
  /// Creates a workflow start response payload.
  const StartWorkflowResponse({this.runId, this.error});

  /// Started workflow run id on success.
  final String? runId;

  /// Error message when workflow start fails.
  final String? error;
}

/// Workflow wait request payload for isolate communication.
class WaitForWorkflowRequest {
  /// Creates a workflow wait request payload.
  const WaitForWorkflowRequest({
    required this.runId,
    required this.workflowName,
    this.pollIntervalMs,
    this.timeoutMs,
  });

  /// Workflow run id to wait on.
  final String runId;

  /// Workflow name used for result decoding.
  final String workflowName;

  /// Poll interval in milliseconds.
  final int? pollIntervalMs;

  /// Timeout in milliseconds.
  final int? timeoutMs;
}

/// Response payload for isolate workflow wait requests.
class WaitForWorkflowResponse {
  /// Creates a workflow wait response payload.
  const WaitForWorkflowResponse({this.result, this.error});

  /// Serialized workflow result payload.
  final Map<String, Object?>? result;

  /// Error message when workflow wait fails.
  final String? error;
}

/// Workflow event emit request payload for isolate communication.
class EmitWorkflowEventRequest {
  /// Creates a workflow event emit request payload.
  const EmitWorkflowEventRequest({
    required this.topic,
    required this.payload,
  });

  /// Workflow event topic to emit.
  final String topic;

  /// Encoded workflow event payload.
  final Map<String, Object?> payload;
}

/// Response payload for isolate workflow event emit requests.
class EmitWorkflowEventResponse {
  /// Creates a workflow event emit response payload.
  const EmitWorkflowEventResponse({this.error});

  /// Error message when workflow event emission fails.
  final String? error;
}

/// Context exposed to task entrypoints regardless of execution environment.
class TaskInvocationContext implements TaskExecutionContext {
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
    enqueuer: enqueuer,
    workflows: workflows,
    workflowEvents: workflowEvents,
  );

  /// Context implementation used when executing inside a worker isolate.
  factory TaskInvocationContext.remote({
    required String id,
    required SendPort controlPort,
    required Map<String, String> headers,
    required Map<String, Object?> meta,
    required int attempt,
    Map<String, Object?> args = const {},
  }) => TaskInvocationContext._(
    id: id,
    args: args,
    headers: headers,
    meta: meta,
    attempt: attempt,
    heartbeat: () => controlPort.send(const HeartbeatSignal()),
    extendLease: (by) async => controlPort.send(ExtendLeaseSignal(by)),
    progress: (percent, {data}) async =>
        controlPort.send(ProgressSignal(percent, data: data)),
    enqueuer: _RemoteTaskEnqueuer(controlPort),
    workflows: _RemoteWorkflowCaller(controlPort),
    workflowEvents: _RemoteWorkflowEventEmitter(controlPort),
  );

  /// Internal constructor shared by local and isolate contexts.
  TaskInvocationContext._({
    required this.id,
    required this.args,
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
    WorkflowCaller? workflows,
    WorkflowEventEmitter? workflowEvents,
  }) : _heartbeat = heartbeat,
       _extendLease = extendLease,
       _progress = progress,
       _enqueuer = enqueuer,
       _workflows = workflows,
       _workflowEvents = workflowEvents;

  /// The unique identifier of the task.
  @override
  final String id;

  @override
  final Map<String, Object?> args;

  /// Headers passed to the task invocation.
  @override
  final Map<String, String> headers;

  /// Invocation metadata (e.g. trace, tenant).
  @override
  final Map<String, Object?> meta;

  /// Current attempt count.
  @override
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

  /// Optional delegate used to start child workflows from the invocation.
  final WorkflowCaller? _workflows;

  /// Optional delegate used to emit workflow events from the invocation.
  final WorkflowEventEmitter? _workflowEvents;

  /// Notify the worker that the task is still running.
  @override
  void heartbeat() => _heartbeat();

  /// Request an extension of the underlying broker lease/visibility timeout.
  @override
  Future<void> extendLease(Duration by) => _extendLease(by);

  /// Report progress back to the worker.
  @override
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
    DateTime? notBefore,
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
      notBefore: notBefore,
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

  @override
  Future<String> startWorkflowRef<TParams, TResult extends Object?>(
    WorkflowRef<TParams, TResult> definition,
    TParams params, {
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    final delegate = _workflows;
    if (delegate == null) {
      throw StateError(
        'TaskInvocationContext has no workflow caller configured',
      );
    }
    return delegate.startWorkflowRef(
      definition,
      params,
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    );
  }

  @override
  Future<String> startWorkflowCall<TParams, TResult extends Object?>(
    WorkflowStartCall<TParams, TResult> call,
  ) {
    final delegate = _workflows;
    if (delegate == null) {
      throw StateError(
        'TaskInvocationContext has no workflow caller configured',
      );
    }
    return delegate.startWorkflowCall(call);
  }

  @override
  Future<WorkflowResult<TResult>?>
  waitForWorkflowRef<TParams, TResult extends Object?>(
    String runId,
    WorkflowRef<TParams, TResult> definition, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) {
    final delegate = _workflows;
    if (delegate == null) {
      throw StateError(
        'TaskInvocationContext has no workflow caller configured',
      );
    }
    return delegate.waitForWorkflowRef(
      runId,
      definition,
      pollInterval: pollInterval,
      timeout: timeout,
    );
  }

  @override
  Future<void> emitValue<T>(
    String topic,
    T value, {
    PayloadCodec<T>? codec,
  }) {
    final delegate = _workflowEvents;
    if (delegate == null) {
      throw StateError(
        'TaskInvocationContext has no workflow event emitter configured',
      );
    }
    return delegate.emitValue(topic, value, codec: codec);
  }

  @override
  Future<void> emitEvent<T>(WorkflowEventRef<T> event, T value) {
    final delegate = _workflowEvents;
    if (delegate == null) {
      throw StateError(
        'TaskInvocationContext has no workflow event emitter configured',
      );
    }
    return delegate.emitEvent(event, value);
  }

  /// Build a caller-bound fluent enqueue request for this invocation.
  BoundTaskEnqueueBuilder<TArgs, TResult> prepareEnqueue<TArgs, TResult>({
    required TaskDefinition<TArgs, TResult> definition,
    required TArgs args,
  }) {
    return BoundTaskEnqueueBuilder(
      enqueuer: this,
      builder: TaskEnqueueBuilder(definition: definition, args: args),
    );
  }

  /// Alias for enqueue.
  @override
  Future<String> spawn(
    String name, {
    Map<String, Object?> args = const {},
    Map<String, String> headers = const {},
    TaskOptions options = const TaskOptions(),
    DateTime? notBefore,
    Map<String, Object?> meta = const {},
    TaskEnqueueOptions? enqueueOptions,
  }) {
    return enqueue(
      name,
      args: args,
      headers: headers,
      options: options,
      notBefore: notBefore,
      meta: meta,
      enqueueOptions: enqueueOptions,
    );
  }

  /// Request a retry of the current task invocation.
  ///
  /// Throws a [TaskRetryRequest] which is intercepted by the worker to
  /// schedule the retry. Override retry policies/time limits per invocation
  /// by passing the optional parameters.
  @override
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
    DateTime? notBefore,
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
          notBefore: notBefore,
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

class _RemoteWorkflowCaller implements WorkflowCaller {
  _RemoteWorkflowCaller(this._controlPort);

  final SendPort _controlPort;

  @override
  Future<String> startWorkflowRef<TParams, TResult extends Object?>(
    WorkflowRef<TParams, TResult> definition,
    TParams params, {
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) async {
    final responsePort = ReceivePort();
    _controlPort.send(
      StartWorkflowSignal(
        StartWorkflowRequest(
          workflowName: definition.name,
          params: definition.encodeParams(params),
          parentRunId: parentRunId,
          ttlMs: ttl?.inMilliseconds,
          cancellationPolicy: cancellationPolicy?.toJson(),
        ),
        responsePort.sendPort,
      ),
    );
    final response = await responsePort.first;
    responsePort.close();
    if (response is StartWorkflowResponse) {
      if (response.error != null) {
        throw StateError(response.error!);
      }
      return response.runId ?? '';
    }
    throw StateError('Unexpected workflow start response: $response');
  }

  @override
  Future<String> startWorkflowCall<TParams, TResult extends Object?>(
    WorkflowStartCall<TParams, TResult> call,
  ) {
    return startWorkflowRef(
      call.definition,
      call.params,
      parentRunId: call.parentRunId,
      ttl: call.ttl,
      cancellationPolicy: call.cancellationPolicy,
    );
  }

  @override
  Future<WorkflowResult<TResult>?>
  waitForWorkflowRef<TParams, TResult extends Object?>(
    String runId,
    WorkflowRef<TParams, TResult> definition, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) async {
    final responsePort = ReceivePort();
    _controlPort.send(
      WaitForWorkflowSignal(
        WaitForWorkflowRequest(
          runId: runId,
          workflowName: definition.name,
          pollIntervalMs: pollInterval.inMilliseconds,
          timeoutMs: timeout?.inMilliseconds,
        ),
        responsePort.sendPort,
      ),
    );
    final response = await responsePort.first;
    responsePort.close();
    if (response is WaitForWorkflowResponse) {
      if (response.error != null) {
        throw StateError(response.error!);
      }
      final resultJson = response.result;
      if (resultJson == null) {
        return null;
      }
      final raw = WorkflowResult<Object?>.fromJson(resultJson);
      return WorkflowResult<TResult>(
        runId: raw.runId,
        status: raw.status,
        state: raw.state,
        value: raw.rawResult == null ? null : definition.decode(raw.rawResult),
        rawResult: raw.rawResult,
        timedOut: raw.timedOut,
      );
    }
    throw StateError('Unexpected workflow wait response: $response');
  }
}

class _RemoteWorkflowEventEmitter implements WorkflowEventEmitter {
  _RemoteWorkflowEventEmitter(this._controlPort);

  final SendPort _controlPort;

  @override
  Future<void> emitValue<T>(
    String topic,
    T value, {
    PayloadCodec<T>? codec,
  }) async {
    final encoded = codec != null ? codec.encodeDynamic(value) : value;
    if (encoded is! Map) {
      throw StateError(
        'TaskInvocationContext workflow events must encode to '
        'Map<String, Object?>, got ${encoded.runtimeType}.',
      );
    }
    final payload = <String, Object?>{};
    for (final entry in encoded.entries) {
      final key = entry.key;
      if (key is! String) {
        throw StateError(
          'TaskInvocationContext workflow event payload keys must be strings, '
          'got ${key.runtimeType}.',
        );
      }
      payload[key] = entry.value;
    }

    final responsePort = ReceivePort();
    _controlPort.send(
      EmitWorkflowEventSignal(
        EmitWorkflowEventRequest(topic: topic, payload: payload),
        responsePort.sendPort,
      ),
    );
    final response = await responsePort.first;
    responsePort.close();
    if (response is EmitWorkflowEventResponse) {
      if (response.error != null) {
        throw StateError(response.error!);
      }
      return;
    }
    throw StateError('Unexpected workflow event response: $response');
  }

  @override
  Future<void> emitEvent<T>(WorkflowEventRef<T> event, T value) {
    return emitValue(event.topic, value, codec: event.codec);
  }
}
