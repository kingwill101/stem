/// Persisted step checkpoint metadata for a workflow run.
class WorkflowStepEntry {
  /// Creates a workflow step entry snapshot.
  const WorkflowStepEntry({
    required this.name,
    required this.value,
    required this.position,
    this.completedAt,
  });

  /// Step identifier as registered in the workflow definition.
  final String name;

  /// Serialized checkpoint value captured after the step succeeded.
  final Object? value;

  /// Zero-based ordinal for rendering in execution order.
  final int position;

  /// Optional timestamp when the checkpoint was recorded.
  final DateTime? completedAt;
}
