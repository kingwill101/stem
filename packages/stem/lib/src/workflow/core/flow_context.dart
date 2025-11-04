import 'flow_step.dart';

/// Context provided to each workflow step invocation.
///
/// The engine replays a step from the beginning whenever the run resumes from a
/// suspension (sleep, awaited event, manual rewind). Steps should therefore
/// treat `sleep`/`awaitEvent` as signalling mechanisms rather than control-flow
/// exits. Use [takeResumeData] to distinguish between the initial invocation and
/// resumption payloads supplied by the runtime.
///
/// [iteration] indicates how many times the step has already completed when
/// `autoVersion` is enabled, allowing handlers to branch per loop iteration or
/// derive unique identifiers.
class FlowContext {
  FlowContext({
    required this.workflow,
    required this.runId,
    required this.stepName,
    required this.params,
    required this.previousResult,
    required this.stepIndex,
    this.iteration = 0,
    Object? resumeData,
  }) : _resumeData = resumeData;

  final String workflow;
  final String runId;
  final String stepName;
  final Map<String, Object?> params;
  final Object? previousResult;
  final int stepIndex;
  final int iteration;

  FlowStepControl? _control;
  Object? _resumeData;

  /// Suspends the workflow until the delay elapses.
  ///
  /// After the delay, the worker replays the **same step** from the top. To
  /// avoid re-scheduling the sleep repeatedly, stash a marker in [data] and
  /// branch on [takeResumeData]; for example:
  ///
  /// ```dart
  /// final resume = ctx.takeResumeData();
  /// if (resume != true) {
  ///   ctx.sleep(const Duration(seconds: 1));
  ///   return null;
  /// }
  /// ```
  FlowStepControl sleep(Duration duration, {Map<String, Object?>? data}) {
    _control = FlowStepControl.sleep(duration, data: data);
    return _control!;
  }

  /// Suspends the workflow until an event with [topic] is emitted.
  ///
  /// When the event bus resumes the run, the payload is made available via
  /// [takeResumeData]. Steps should always read and clear the payload to avoid
  /// processing the same message on subsequent replays.
  FlowStepControl awaitEvent(
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
  }) {
    _control = FlowStepControl.awaitTopic(
      topic,
      deadline: deadline,
      data: data,
    );
    return _control!;
  }

  /// Injects a payload that will be returned the next time [takeResumeData] is
  /// called. Primarily used by the runtime; tests may also leverage it to mock
  /// resumption data.
  void resumeWith(Object? payload) {
    _resumeData = payload;
  }

  /// Returns the payload supplied when the run was resumed, or `null` if this
  /// is the first invocation.
  ///
  /// The method consumes the payload so subsequent calls during the same step
  /// return `null`. This makes it safe to guard control-flow with a simple
  /// `if (takeResumeData() == null) { ... }` pattern.
  Object? takeResumeData() {
    final value = _resumeData;
    _resumeData = null;
    return value;
  }

  /// Consumes the control directive queued by [sleep] or [awaitEvent]. Steps do
  /// not normally call this directly; it exists for the runtime orchestrator.
  FlowStepControl? takeControl() {
    final value = _control;
    _control = null;
    return value;
  }

  /// Returns a stable idempotency key derived from the workflow, run, and
  /// [scope]. Defaults to the current [stepName] (including iteration suffix
  /// when [iteration] > 0) when no scope is provided.
  String idempotencyKey([String? scope]) {
    final defaultScope = iteration > 0 ? '$stepName#$iteration' : stepName;
    final effectiveScope = (scope == null || scope.isEmpty)
        ? defaultScope
        : scope;
    return '$workflow/$runId/$effectiveScope';
  }
}
