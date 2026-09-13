/// Result of one bounded runnable-workflow recovery scan.
///
/// Enqueueing is a recovery hint, not proof that a workflow executed. Another
/// worker may already have a delivery; normal execution claims and checkpoint
/// replay arbitrate duplicates. The report is not a durable log.
final class WorkflowRecoveryReport {
  /// Copies the scan result into immutable collections.
  WorkflowRecoveryReport({
    Iterable<String> enqueuedRunIds = const [],
    Iterable<String> skippedRunIds = const [],
    Map<String, String> errors = const {},
  }) : enqueuedRunIds = List.unmodifiable(enqueuedRunIds),
       skippedRunIds = List.unmodifiable(skippedRunIds),
       errors = Map.unmodifiable(errors);

  /// Runs whose continuation was successfully enqueued.
  final List<String> enqueuedRunIds;

  /// Candidates no longer runnable or not registered with this host/runtime.
  final List<String> skippedRunIds;

  /// Per-run failures encountered while reading or enqueueing candidates.
  final Map<String, String> errors;
}
