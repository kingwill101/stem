import 'dart:async';

import 'package:stem/src/workflow/core/flow.dart' show Flow;
import 'package:stem/src/workflow/core/flow_context.dart';
import 'package:stem/src/workflow/workflow.dart' show Flow;
import 'package:stem/stem.dart' show Flow;

/// Node in a workflow [Flow].
///
/// The [handler] may execute multiple times when a run resumes from a
/// suspension or retry. Ensure the logic is idempotent and uses values stored
/// in the [FlowContext] (e.g. via `context.previousResult` or
/// `context.takeResumeData()`). When [autoVersion] is `true`, each time the
/// step completes its checkpoint is stored as `<name>#<iteration>` so repeated
/// executions do not overwrite previous results.
class FlowStep {
  /// Creates a workflow step definition.
  FlowStep({
    required this.name,
    required this.handler,
    this.autoVersion = false,
  });

  /// Step name used for checkpoints and scheduling.
  final String name;

  /// Handler invoked when the step executes.
  final FutureOr<dynamic> Function(FlowContext context) handler;

  /// Whether to auto-version checkpoints across repeated executions.
  final bool autoVersion;
}

/// Control directive emitted by a workflow step to suspend execution.
class FlowStepControl {
  /// Creates a control directive with the given [type].
  FlowStepControl._(
    this.type, {
    this.delay,
    this.topic,
    this.deadline,
    this.data,
  });

  /// Suspend the run until [duration] elapses.
  factory FlowStepControl.sleep(
    Duration duration, {
    Map<String, Object?>? data,
  }) => FlowStepControl._(FlowControlType.sleep, delay: duration, data: data);

  /// Suspend the run until an event with [topic] arrives.
  factory FlowStepControl.awaitTopic(
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
  }) => FlowStepControl._(
    FlowControlType.waitForEvent,
    topic: topic,
    deadline: deadline,
    data: data,
  );

  /// Continue execution without suspending.
  factory FlowStepControl.continueRun() =>
      FlowStepControl._(FlowControlType.continueRun);

  /// Control type emitted by the step.
  final FlowControlType type;

  /// Delay duration for sleep directives.
  final Duration? delay;

  /// Topic to await for event directives.
  final String? topic;

  /// Optional deadline for event waits.
  final DateTime? deadline;

  /// Additional data to persist with the suspension.
  final Map<String, Object?>? data;
}

/// Enumerates the suspension control types.
enum FlowControlType {
  /// Continue execution immediately.
  continueRun,

  /// Suspend execution for a duration.
  sleep,

  /// Suspend execution until an event is received.
  waitForEvent,
}
