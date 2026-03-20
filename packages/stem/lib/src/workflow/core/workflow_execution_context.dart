import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/payload_codec.dart';
import 'package:stem/src/core/payload_map.dart';
import 'package:stem/src/workflow/core/workflow_ref.dart';
import 'package:stem/src/workflow/core/workflow_resume_context.dart';

/// Shared execution context surface for flow steps and script checkpoints.
///
/// This keeps the common workflow-authoring capabilities on one type:
/// metadata about the current step/checkpoint, task enqueueing, child-workflow
/// starts, and durable suspension helpers.
abstract interface class WorkflowExecutionContext
    implements TaskEnqueuer, WorkflowCaller, WorkflowResumeContext {
  /// Name of the workflow currently executing.
  String get workflow;

  /// Identifier for the workflow run.
  String get runId;

  /// Name of the current step or checkpoint.
  String get stepName;

  /// Zero-based step or checkpoint index.
  int get stepIndex;

  /// Iteration count for looped steps or checkpoints.
  int get iteration;

  /// Parameters provided when the workflow started.
  Map<String, Object?> get params;

  /// Result of the previous step or checkpoint, if any.
  Object? get previousResult;

  /// Returns a stable idempotency key derived from workflow/run/step state.
  String idempotencyKey([String? scope]);

  /// Optional enqueuer for scheduling tasks with workflow metadata.
  TaskEnqueuer? get enqueuer;

  /// Optional typed workflow caller for spawning child workflows.
  WorkflowCaller? get workflows;
}

/// Typed read helpers for workflow start parameters.
extension WorkflowExecutionContextParams on WorkflowExecutionContext {
  /// Returns the decoded workflow parameter for [key], or `null`.
  T? param<T>(String key, {PayloadCodec<T>? codec}) {
    return params.value<T>(key, codec: codec);
  }

  /// Returns the decoded workflow parameter for [key], or [fallback].
  T paramOr<T>(String key, T fallback, {PayloadCodec<T>? codec}) {
    return params.valueOr<T>(key, fallback, codec: codec);
  }

  /// Returns the decoded workflow parameter for [key], throwing when absent.
  T requiredParam<T>(String key, {PayloadCodec<T>? codec}) {
    return params.requiredValue<T>(key, codec: codec);
  }

  /// Returns the decoded workflow parameter DTO for [key], or `null`.
  T? paramJson<T>(
    String key, {
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    return params.valueJson<T>(
      key,
      decode: decode,
      typeName: typeName,
    );
  }

  /// Returns the decoded workflow parameter DTO for [key], or [fallback].
  T paramJsonOr<T>(
    String key,
    T fallback, {
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    return params.valueJsonOr<T>(
      key,
      fallback,
      decode: decode,
      typeName: typeName,
    );
  }

  /// Returns the decoded workflow parameter DTO for [key], throwing when
  /// absent.
  T requiredParamJson<T>(
    String key, {
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    return params.requiredValueJson<T>(
      key,
      decode: decode,
      typeName: typeName,
    );
  }
}

/// Typed read helpers for prior workflow step and checkpoint values.
extension WorkflowExecutionContextValues on WorkflowExecutionContext {
  /// Returns the decoded prior step/checkpoint value as [T], or `null`.
  ///
  /// When [codec] is supplied, a non-`T` durable payload is decoded through
  /// that codec before being returned.
  T? previousValue<T>({PayloadCodec<T>? codec}) {
    final value = previousResult;
    if (value == null) return null;
    if (codec != null && value is! T) {
      return codec.decodeDynamic(value) as T;
    }
    return value as T;
  }

  /// Returns the decoded prior step/checkpoint value as [T], throwing when the
  /// workflow does not yet have a previous result.
  T requiredPreviousValue<T>({PayloadCodec<T>? codec}) {
    final value = previousValue<T>(codec: codec);
    if (value == null) {
      throw StateError('WorkflowExecutionContext.previousResult is null.');
    }
    return value;
  }

  /// Returns the decoded prior step/checkpoint value as a typed DTO, or
  /// `null`.
  T? previousJson<T>({
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    final value = previousResult;
    if (value == null) return null;
    return PayloadCodec<T>.json(
      decode: decode,
      typeName: typeName,
    ).decode(value);
  }

  /// Returns the decoded prior step/checkpoint DTO, or [fallback].
  T previousJsonOr<T>(
    T fallback, {
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    return previousJson<T>(
          decode: decode,
          typeName: typeName,
        ) ??
        fallback;
  }

  /// Returns the decoded prior step/checkpoint DTO, throwing when absent.
  T requiredPreviousJson<T>({
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    final value = previousJson<T>(
      decode: decode,
      typeName: typeName,
    );
    if (value == null) {
      throw StateError('WorkflowExecutionContext.previousResult is null.');
    }
    return value;
  }
}
