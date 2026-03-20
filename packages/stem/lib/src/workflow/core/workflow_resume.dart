import 'dart:async';

import 'package:stem/src/core/payload_codec.dart';
import 'package:stem/src/workflow/core/flow_context.dart';
import 'package:stem/src/workflow/core/flow_step.dart';
import 'package:stem/src/workflow/core/workflow_event_ref.dart';
import 'package:stem/src/workflow/core/workflow_script_context.dart';

/// Internal control-flow signal used by expression-style suspension helpers.
///
/// The workflow runtime catches this after a helper has already scheduled the
/// corresponding sleep or event wait directive. User code should not catch it.
class WorkflowSuspensionSignal implements Exception {
  /// Creates a durable suspension control-flow signal.
  const WorkflowSuspensionSignal();
}

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

  /// Suspends once for [duration] and resumes by replaying the same step.
  ///
  /// This enables expression-style flow logic:
  ///
  /// ```dart
  /// await ctx.sleepFor(duration: const Duration(seconds: 1));
  /// ```
  Future<void> sleepFor({
    required Duration duration,
    Map<String, Object?>? data,
  }) async {
    final resume = takeResumeData();
    if (resume != null) {
      return;
    }
    sleep(duration, data: data);
    throw const WorkflowSuspensionSignal();
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

  /// Suspends until [topic] is emitted, then returns the resumed payload.
  Future<T> waitForEvent<T>({
    required String topic,
    DateTime? deadline,
    Map<String, Object?>? data,
    PayloadCodec<T>? codec,
  }) async {
    final payload = takeResumeValue<T>(codec: codec);
    if (payload != null) {
      return payload;
    }
    awaitEvent(topic, deadline: deadline, data: data);
    throw const WorkflowSuspensionSignal();
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

  /// Suspends once for [duration] and resumes by replaying the same
  /// checkpoint.
  Future<void> sleepFor({
    required Duration duration,
    Map<String, Object?>? data,
  }) async {
    final resume = takeResumeData();
    if (resume != null) {
      return;
    }
    await sleep(duration, data: data);
    throw const WorkflowSuspensionSignal();
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

  /// Suspends until [topic] is emitted, then returns the resumed payload.
  Future<T> waitForEvent<T>({
    required String topic,
    DateTime? deadline,
    Map<String, Object?>? data,
    PayloadCodec<T>? codec,
  }) async {
    final payload = takeResumeValue<T>(codec: codec);
    if (payload != null) {
      return payload;
    }
    await awaitEvent(topic, deadline: deadline, data: data);
    throw const WorkflowSuspensionSignal();
  }
}

/// Direct typed wait helpers on [WorkflowEventRef].
///
/// These mirror `event.emit(...)` so typed workflow events can stay on the
/// event-ref surface for both emit and wait paths.
extension WorkflowEventRefWaitExtension<T> on WorkflowEventRef<T> {
  /// Registers a low-level flow-control wait while keeping the typed event ref
  /// on the call site.
  FlowStepControl awaitOn(
    FlowContext step, {
    DateTime? deadline,
    Map<String, Object?>? data,
  }) {
    return step.awaitEvent(
      topic,
      deadline: deadline,
      data: data,
    );
  }

  /// Registers an event wait and returns the resumed payload on the legacy
  /// null-then-resume path.
  ///
  /// [waiter] must be a [FlowContext] or [WorkflowScriptStepContext].
  T? waitValue(
    Object waiter, {
    DateTime? deadline,
    Map<String, Object?>? data,
  }) {
    if (waiter case final FlowContext context) {
      return context.waitForEventValue<T>(
        topic,
        deadline: deadline,
        data: data,
        codec: codec,
      );
    }
    if (waiter case final WorkflowScriptStepContext context) {
      return context.waitForEventValue<T>(
        topic,
        deadline: deadline,
        data: data,
        codec: codec,
      );
    }
    throw ArgumentError.value(
      waiter,
      'waiter',
      'WorkflowEventRef.waitValue requires a FlowContext or '
          'WorkflowScriptStepContext.',
    );
  }

  /// Suspends until this event is emitted, then returns the decoded payload.
  ///
  /// [waiter] must be a [FlowContext] or [WorkflowScriptStepContext].
  Future<T> wait(
    Object waiter, {
    DateTime? deadline,
    Map<String, Object?>? data,
  }) {
    if (waiter case final FlowContext context) {
      return context.waitForEvent<T>(
        topic: topic,
        deadline: deadline,
        data: data,
        codec: codec,
      );
    }
    if (waiter case final WorkflowScriptStepContext context) {
      return context.waitForEvent<T>(
        topic: topic,
        deadline: deadline,
        data: data,
        codec: codec,
      );
    }
    throw ArgumentError.value(
      waiter,
      'waiter',
      'WorkflowEventRef.wait requires a FlowContext or '
          'WorkflowScriptStepContext.',
    );
  }
}
