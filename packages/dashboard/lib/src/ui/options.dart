/// View options used by the tasks page renderer.
class TasksPageOptions {
  /// Creates task page options with optional overrides.
  const TasksPageOptions({
    this.sortKey = 'queue',
    this.descending = false,
    this.filter,
    this.flashKey,
    this.errorKey,
  });

  /// Sort key used for queue ordering.
  final String sortKey;

  /// Whether sorting should be descending.
  final bool descending;

  /// Optional queue filter text.
  final String? filter;

  /// Optional flash message key for UI alerts.
  final String? flashKey;

  /// Optional error message key for UI alerts.
  final String? errorKey;

  /// Whether a non-empty filter value is set.
  bool get hasFilter => filter != null && filter!.isNotEmpty;
}

/// View options used by the workers page renderer.
class WorkersPageOptions {
  /// Creates worker page options with optional overrides.
  const WorkersPageOptions({this.flashMessage, this.errorMessage, this.scope});

  /// Optional flash message for the UI.
  final String? flashMessage;

  /// Optional error message for the UI.
  final String? errorMessage;

  /// Optional worker scope filter.
  final String? scope;

  /// Whether a non-empty flash message is set.
  bool get hasFlash => flashMessage != null && flashMessage!.isNotEmpty;

  /// Whether a non-empty error message is set.
  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;

  /// Whether a non-empty scope value is set.
  bool get hasScope => scope != null && scope!.isNotEmpty;
}
