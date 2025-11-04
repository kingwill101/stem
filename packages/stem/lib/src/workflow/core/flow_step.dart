import 'dart:async';

import 'flow_context.dart';

/// Node in a workflow [Flow].
///
/// The [handler] may execute multiple times when a run resumes from a
/// suspension or retry. Ensure the logic is idempotent and uses values stored
/// in the [FlowContext] (e.g. via `context.previousResult` or
/// `context.takeResumeData()`).
class FlowStep {
  FlowStep({required this.name, required this.handler});

  final String name;
  final FutureOr<dynamic> Function(FlowContext context) handler;
}

/// Control directive emitted by a workflow step to suspend execution.
class FlowStepControl {
  FlowStepControl._(
    this.type, {
    this.delay,
    this.topic,
    this.deadline,
    this.data,
  });

  final FlowControlType type;
  final Duration? delay;
  final String? topic;
  final DateTime? deadline;
  final Map<String, Object?>? data;

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
}

enum FlowControlType { continueRun, sleep, waitForEvent }
