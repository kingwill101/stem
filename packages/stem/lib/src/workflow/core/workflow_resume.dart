import 'package:stem/src/core/payload_codec.dart';
import 'package:stem/src/workflow/core/flow_context.dart';
import 'package:stem/src/workflow/core/workflow_script_context.dart';

/// Typed resume helpers for durable workflow suspensions.
extension FlowContextResumeValues on FlowContext {
  /// Returns the next resume payload as [T] and consumes it.
  ///
  /// When [codec] is provided, the stored durable payload is decoded through
  /// that codec before being returned.
  T? takeResumeValue<T>({PayloadCodec<T>? codec}) {
    final payload = takeResumeData();
    if (payload == null) return null;
    if (codec != null) return codec.decodeDynamic(payload) as T;
    return payload as T;
  }
}

/// Typed resume helpers for durable script checkpoints.
extension WorkflowScriptStepResumeValues on WorkflowScriptStepContext {
  /// Returns the next resume payload as [T] and consumes it.
  ///
  /// When [codec] is provided, the stored durable payload is decoded through
  /// that codec before being returned.
  T? takeResumeValue<T>({PayloadCodec<T>? codec}) {
    final payload = takeResumeData();
    if (payload == null) return null;
    if (codec != null) return codec.decodeDynamic(payload) as T;
    return payload as T;
  }
}
