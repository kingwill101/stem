// Copyright (c) 2025 Glenford Williams <hey@glenfordwilliams.com>
// SPDX-License-Identifier: MIT

import 'dart:async';

/// Reconstructed executable cleanup handler; only its stable ID is persisted.
typedef WorkflowCompensationHandler = FutureOr<void> Function(
  WorkflowCompensationContext context,
  Object? input,
);

/// Context for one claimed compensation attempt.
final class WorkflowCompensationContext {
  /// Creates an execution context with an independent cleanup lease heartbeat.
  const WorkflowCompensationContext({
    required this.runId,
    required this.stepName,
    required this.handler,
    required this.attempt,
    required Future<void> Function() heartbeat,
  }) : _heartbeat = heartbeat;

  /// Failed workflow run being cleaned up.
  final String runId;

  /// Successful checkpoint whose encoded result is being compensated.
  final String stepName;

  /// Stable registered handler ID.
  final String handler;

  /// One-based lifetime cleanup attempt count.
  final int attempt;

  final Future<void> Function() _heartbeat;

  /// Stable logical-operation key, shared across retry attempts.
  String get idempotencyKey =>
      '$runId/${Uri.encodeComponent(stepName)}/compensate/'
      '${Uri.encodeComponent(handler)}';

  /// Extends the journal lease while a long cleanup operation is active.
  Future<void> heartbeat() => _heartbeat();
}
