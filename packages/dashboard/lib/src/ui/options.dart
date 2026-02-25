import 'package:stem/stem.dart' show TaskState;

/// View options used by the tasks page renderer.
class TasksPageOptions {
  /// Creates task page options with optional overrides.
  const TasksPageOptions({
    this.sortKey = 'queue',
    this.descending = false,
    this.filter,
    this.namespaceFilter,
    this.taskFilter,
    this.runId,
    this.stateFilter,
    this.flashKey,
    this.errorKey,
    this.page = 1,
    this.pageSize = 25,
    this.hasNextPage = false,
    this.hasPreviousPage = false,
  });

  /// Sort key used for queue ordering.
  final String sortKey;

  /// Whether sorting should be descending.
  final bool descending;

  /// Optional queue filter text.
  final String? filter;

  /// Optional namespace filter text.
  final String? namespaceFilter;

  /// Optional task name filter text.
  final String? taskFilter;

  /// Optional workflow run id filter.
  final String? runId;

  /// Optional lifecycle state filter for recent task statuses.
  final TaskState? stateFilter;

  /// Optional flash message key for UI alerts.
  final String? flashKey;

  /// Optional error message key for UI alerts.
  final String? errorKey;

  /// Current page number (1-based).
  final int page;

  /// Number of task status records requested for a page.
  final int pageSize;

  /// Whether another page exists after [page].
  final bool hasNextPage;

  /// Whether a page exists before [page].
  final bool hasPreviousPage;

  /// Whether a non-empty filter value is set.
  bool get hasFilter => filter != null && filter!.isNotEmpty;

  /// Whether a non-empty namespace filter value is set.
  bool get hasNamespaceFilter =>
      namespaceFilter != null && namespaceFilter!.isNotEmpty;

  /// Whether a non-empty task filter value is set.
  bool get hasTaskFilter => taskFilter != null && taskFilter!.isNotEmpty;

  /// Whether a non-empty run id filter value is set.
  bool get hasRunIdFilter => runId != null && runId!.isNotEmpty;

  /// Whether a status filter is set.
  bool get hasStateFilter => stateFilter != null;

  /// Zero-based offset derived from [page] and [pageSize].
  int get offset => (page - 1) * pageSize;

  /// Whether pagination controls should be shown.
  bool get hasPagination => hasPreviousPage || hasNextPage || page > 1;

  /// Creates a copy with selected fields replaced.
  TasksPageOptions copyWith({
    String? sortKey,
    bool? descending,
    String? filter,
    String? namespaceFilter,
    String? taskFilter,
    String? runId,
    TaskState? stateFilter,
    String? flashKey,
    String? errorKey,
    int? page,
    int? pageSize,
    bool? hasNextPage,
    bool? hasPreviousPage,
  }) {
    return TasksPageOptions(
      sortKey: sortKey ?? this.sortKey,
      descending: descending ?? this.descending,
      filter: filter ?? this.filter,
      namespaceFilter: namespaceFilter ?? this.namespaceFilter,
      taskFilter: taskFilter ?? this.taskFilter,
      runId: runId ?? this.runId,
      stateFilter: stateFilter ?? this.stateFilter,
      flashKey: flashKey ?? this.flashKey,
      errorKey: errorKey ?? this.errorKey,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      hasNextPage: hasNextPage ?? this.hasNextPage,
      hasPreviousPage: hasPreviousPage ?? this.hasPreviousPage,
    );
  }
}

/// View options used by the workers page renderer.
class WorkersPageOptions {
  /// Creates worker page options with optional overrides.
  const WorkersPageOptions({
    this.flashMessage,
    this.errorMessage,
    this.scope,
    this.namespaceFilter,
  });

  /// Optional flash message for the UI.
  final String? flashMessage;

  /// Optional error message for the UI.
  final String? errorMessage;

  /// Optional worker scope filter.
  final String? scope;

  /// Optional namespace filter.
  final String? namespaceFilter;

  /// Whether a non-empty flash message is set.
  bool get hasFlash => flashMessage != null && flashMessage!.isNotEmpty;

  /// Whether a non-empty error message is set.
  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;

  /// Whether a non-empty scope value is set.
  bool get hasScope => scope != null && scope!.isNotEmpty;

  /// Whether a non-empty namespace filter value is set.
  bool get hasNamespaceFilter =>
      namespaceFilter != null && namespaceFilter!.isNotEmpty;
}

/// View options used by the failures page renderer.
class FailuresPageOptions {
  /// Creates failure diagnostics options with optional overrides.
  const FailuresPageOptions({this.queue, this.flashMessage, this.errorMessage});

  /// Optional queue filter.
  final String? queue;

  /// Optional flash message for the UI.
  final String? flashMessage;

  /// Optional error message for the UI.
  final String? errorMessage;

  /// Whether a non-empty queue filter is set.
  bool get hasQueueFilter => queue != null && queue!.isNotEmpty;

  /// Whether a non-empty flash message is set.
  bool get hasFlash => flashMessage != null && flashMessage!.isNotEmpty;

  /// Whether a non-empty error message is set.
  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;
}

/// View options used by the search page renderer.
class SearchPageOptions {
  /// Creates search options with optional overrides.
  const SearchPageOptions({this.query, this.scope = 'all'});

  /// Free-text search query.
  final String? query;

  /// Scope filter (`all`, `tasks`, `workers`, `queues`, `audit`).
  final String scope;

  /// Whether a query is present.
  bool get hasQuery => query != null && query!.trim().isNotEmpty;
}

/// View options used by the namespaces page renderer.
class NamespacesPageOptions {
  /// Creates namespace options with optional overrides.
  const NamespacesPageOptions({this.namespace});

  /// Optional namespace filter text.
  final String? namespace;

  /// Whether namespace filter is set.
  bool get hasNamespace => namespace != null && namespace!.isNotEmpty;
}

/// View options used by the workflows page renderer.
class WorkflowsPageOptions {
  /// Creates workflows options with optional overrides.
  const WorkflowsPageOptions({this.workflow, this.runId});

  /// Optional workflow name filter text.
  final String? workflow;

  /// Optional run-id filter text.
  final String? runId;

  /// Whether workflow filter is set.
  bool get hasWorkflow => workflow != null && workflow!.isNotEmpty;

  /// Whether run-id filter is set.
  bool get hasRunId => runId != null && runId!.isNotEmpty;
}

/// View options used by the jobs page renderer.
class JobsPageOptions {
  /// Creates jobs options with optional overrides.
  const JobsPageOptions({this.task, this.queue});

  /// Optional task-name filter.
  final String? task;

  /// Optional queue filter.
  final String? queue;

  /// Whether task filter is set.
  bool get hasTask => task != null && task!.isNotEmpty;

  /// Whether queue filter is set.
  bool get hasQueue => queue != null && queue!.isNotEmpty;
}
