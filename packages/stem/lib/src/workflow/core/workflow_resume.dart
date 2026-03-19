import 'dart:async';

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

  /// Suspends the current step with [sleep] on the first invocation and
  /// returns `true` once the step resumes.
  ///
  /// This helper is for the common:
  ///
  /// ```dart
  /// if (ctx.takeResumeData() == null) {
  ///   ctx.sleep(duration);
  ///   return null;
  /// }
  /// ```
  ///
  /// pattern.
  bool sleepUntilResumed(
    Duration duration, {
    Map<String, Object?>? data,
  }) {
    final resume = takeResumeData();
    if (resume != null) {
      return true;
    }
    sleep(duration, data: data);
    return false;
  }

  /// Returns the next event payload as [T] when the step has resumed, or
  /// registers an event wait and returns `null` on the first invocation.
  ///
  /// This helper is for the common:
  ///
  /// ```dart
  /// final payload = ctx.takeResumeValue<T>(codec: codec);
  /// if (payload == null) {
  ///   ctx.awaitEvent(topic);
  ///   return null;
  /// }
  /// ```
  ///
  /// pattern.
  T? waitForEventValue<T>(
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
    PayloadCodec<T>? codec,
  }) {
    final payload = takeResumeValue<T>(codec: codec);
    if (payload != null) {
      return payload;
    }
    awaitEvent(topic, deadline: deadline, data: data);
    return null;
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

  /// Suspends the current checkpoint with [sleep] on the first invocation and
  /// returns `true` once the checkpoint resumes.
  bool sleepUntilResumed(
    Duration duration, {
    Map<String, Object?>? data,
  }) {
    final resume = takeResumeData();
    if (resume != null) {
      return true;
    }
    unawaited(sleep(duration, data: data));
    return false;
  }

  /// Returns the next event payload as [T] when the checkpoint has resumed, or
  /// registers an event wait and returns `null` on the first invocation.
  T? waitForEventValue<T>(
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
    PayloadCodec<T>? codec,
  }) {
    final payload = takeResumeValue<T>(codec: codec);
    if (payload != null) {
      return payload;
    }
    unawaited(awaitEvent(topic, deadline: deadline, data: data));
    return null;
  }
}
