/// Lifecycle state of a workflow run.
enum WorkflowStatus {
  /// Workflow is currently running.
  running,

  /// Workflow execution is suspended and can be resumed.
  suspended,

  /// Workflow completed successfully.
  completed,

  /// Workflow failed with an error.
  failed,

  /// Workflow was cancelled before completion.
  cancelled,
}
