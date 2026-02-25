// Public helper functions in this file are intentionally undocumented to keep
// UI template files lightweight.
// ignore_for_file: public_member_api_docs

import 'package:stem_dashboard/src/services/models.dart';
import 'package:stem_dashboard/src/ui/options.dart';
import 'package:stem_dashboard/src/ui/shared.dart';

String buildSearchContent({
  required SearchPageOptions options,
  required List<QueueSummary> queues,
  required List<WorkerStatus> workers,
  required List<DashboardTaskStatusEntry> taskStatuses,
  required List<DashboardAuditEntry> auditEntries,
}) {
  final queryRaw = options.query?.trim() ?? '';
  final query = queryRaw.toLowerCase();
  final taskMatches = _isScope(options.scope, 'tasks')
      ? _searchTasks(taskStatuses, query)
      : const <DashboardTaskStatusEntry>[];
  final workerMatches = _isScope(options.scope, 'workers')
      ? _searchWorkers(workers, query)
      : const <WorkerStatus>[];
  final queueMatches = _isScope(options.scope, 'queues')
      ? _searchQueues(queues, query)
      : const <QueueSummary>[];
  final auditMatches = _isScope(options.scope, 'audit')
      ? _searchAudit(auditEntries, query)
      : const <DashboardAuditEntry>[];

  return '''
<section class="page-header rounded-2xl border border-slate-300/15 bg-slate-900/45 px-5 py-5">
  <h1>Search</h1>
  <p class="page-subtitle">
    Global lookup across tasks, workers, queues, and audit trails with one query.
  </p>
</section>

<section class="cards">
  ${buildMetricCard('Task hits', formatInt(taskMatches.length), 'Matching task statuses by id/name/queue/workflow/error.')}
  ${buildMetricCard('Worker hits', formatInt(workerMatches.length), 'Matching worker IDs and queue assignments.')}
  ${buildMetricCard('Queue hits', formatInt(queueMatches.length), 'Matching queue names.')}
  ${buildMetricCard('Audit hits', formatInt(auditMatches.length), 'Matching operator actions and alert records.')}
</section>

<form class="filter-form rounded-2xl border border-slate-300/15 bg-slate-900/40 p-4" action="/search" method="get" data-turbo-frame="dashboard-content">
  <label class="filter-label" for="search-query">Query</label>
  <input id="search-query" name="q" value="${escapeHtml(queryRaw)}" placeholder="task id, run id, queue, worker" />
  <label class="filter-label" for="search-scope">Scope</label>
  ${buildSearchScopeSelect(options.scope)}
  <button type="submit">Search</button>
</form>

<section class="table-card mb-7 ring-1 ring-inset ring-sky-300/10">
  <table>
    <thead>
      <tr>
        <th scope="col">Saved Views</th>
        <th scope="col">Intent</th>
      </tr>
    </thead>
    <tbody>
      ${buildSavedViewRow('/tasks?state=failed', 'Failed tasks', 'Recent terminal failures')}
      ${buildSavedViewRow('/tasks?state=running', 'Running tasks', 'Investigate long-running tasks')}
      ${buildSavedViewRow('/tasks?sort=pending&direction=desc', 'Backlog hotspots', 'Queues with highest pending load')}
      ${buildSavedViewRow('/failures', 'Failure diagnostics', 'Grouped error fingerprints + replay controls')}
      ${buildSavedViewRow('/workers', 'Worker health', 'Capacity and control plane visibility')}
      ${buildSavedViewRow('/audit', 'Audit log', 'Operator actions and alert deliveries')}
    </tbody>
  </table>
</section>

${buildSearchTable(
    title: 'Tasks',
    emptyMessage: options.hasQuery ? 'No task results matched this query.' : 'Enter a query to search tasks.',
    headers: const ['Task ID', 'Task', 'Queue', 'State', 'Updated'],
    rows: taskMatches.take(40).map((task) => '''
<tr>
  <td><a href="/tasks/detail?id=${Uri.encodeQueryComponent(task.id)}" data-turbo-frame="dashboard-content"><code>${escapeHtml(task.id)}</code></a></td>
  <td>${escapeHtml(task.taskName)}</td>
  <td><span class="pill">${escapeHtml(task.queue)}</span></td>
  <td>${buildTaskStatePill(task.state)}</td>
  <td class="muted">${formatRelative(task.updatedAt)}</td>
</tr>
''').toList(growable: false),
  )}

${buildSearchTable(
    title: 'Workers',
    emptyMessage: options.hasQuery ? 'No worker results matched this query.' : 'Enter a query to search workers.',
    headers: const ['Worker', 'Queues', 'Inflight', 'Heartbeat'],
    rows: workerMatches.take(30).map((worker) => '''
<tr>
  <td>${escapeHtml(worker.workerId)}</td>
  <td>${worker.queues.isEmpty ? '<span class="muted">—</span>' : worker.queues.map((queue) => '<span class="pill">${escapeHtml(queue.name)}</span>').join(' ')}</td>
  <td>${formatInt(worker.inflight)}</td>
  <td class="muted">${formatRelative(worker.timestamp)}</td>
</tr>
''').toList(growable: false),
  )}

${buildSearchTable(
    title: 'Queues',
    emptyMessage: options.hasQuery ? 'No queue results matched this query.' : 'Enter a query to search queues.',
    headers: const ['Queue', 'Pending', 'Inflight', 'Dead letters'],
    rows: queueMatches.take(30).map((queue) => '''
<tr>
  <td><span class="pill">${escapeHtml(queue.queue)}</span></td>
  <td>${formatInt(queue.pending)}</td>
  <td>${formatInt(queue.inflight)}</td>
  <td>${formatInt(queue.deadLetters)}</td>
</tr>
''').toList(growable: false),
  )}

${buildSearchTable(
    title: 'Audit',
    emptyMessage: options.hasQuery ? 'No audit entries matched this query.' : 'Enter a query to search audit events.',
    headers: const ['Time', 'Kind', 'Action', 'Status', 'Summary'],
    rows: auditMatches.take(60).map((entry) => '''
<tr>
  <td class="muted">${formatRelative(entry.timestamp)}</td>
  <td>${escapeHtml(entry.kind)}</td>
  <td>${escapeHtml(entry.action)}</td>
  <td><span class="pill ${entry.status == 'ok' || entry.status == 'sent'
        ? 'success'
        : entry.status == 'error'
        ? 'error'
        : 'warning'}">${escapeHtml(entry.status)}</span></td>
  <td class="muted">${escapeHtml(entry.summary ?? '—')}</td>
</tr>
''').toList(growable: false),
  )}
''';
}

String buildSearchScopeSelect(String currentScope) {
  String option(String value, String label) {
    final selected = currentScope == value ? ' selected' : '';
    return '<option value="$value"$selected>$label</option>';
  }

  return '''
<select id="search-scope" name="scope">
  ${option('all', 'All')}
  ${option('tasks', 'Tasks')}
  ${option('workers', 'Workers')}
  ${option('queues', 'Queues')}
  ${option('audit', 'Audit')}
</select>
''';
}

String buildSavedViewRow(String href, String label, String intent) {
  return '''
<tr>
  <td><a class="font-semibold text-sky-200 hover:text-sky-100" href="$href" data-turbo-frame="dashboard-content">${escapeHtml(label)}</a></td>
  <td class="muted">${escapeHtml(intent)}</td>
</tr>
''';
}

String buildSearchTable({
  required String title,
  required String emptyMessage,
  required List<String> headers,
  required List<String> rows,
}) {
  return '''
<section class="table-card mb-7 ring-1 ring-inset ring-sky-300/10">
  <header class="border-b border-slate-300/10 px-4 py-3">
    <h2 class="text-sm font-semibold uppercase tracking-wider text-slate-300">${escapeHtml(title)}</h2>
  </header>
  <table>
    <thead>
      <tr>
        ${headers.map((header) => '<th scope="col">${escapeHtml(header)}</th>').join()}
      </tr>
    </thead>
    <tbody>
      ${rows.isEmpty ? '<tr><td colspan="${headers.length}" class="muted">${escapeHtml(emptyMessage)}</td></tr>' : rows.join()}
    </tbody>
  </table>
</section>
''';
}

bool _isScope(String scope, String target) => scope == 'all' || scope == target;

List<DashboardTaskStatusEntry> _searchTasks(
  List<DashboardTaskStatusEntry> tasks,
  String query,
) {
  if (query.isEmpty) return const [];
  return tasks
      .where((task) {
        return task.id.toLowerCase().contains(query) ||
            task.taskName.toLowerCase().contains(query) ||
            task.queue.toLowerCase().contains(query) ||
            (task.runId?.toLowerCase().contains(query) ?? false) ||
            (task.errorMessage?.toLowerCase().contains(query) ?? false);
      })
      .toList(growable: false);
}

List<WorkerStatus> _searchWorkers(List<WorkerStatus> workers, String query) {
  if (query.isEmpty) return const [];
  return workers
      .where((worker) {
        if (worker.workerId.toLowerCase().contains(query)) return true;
        for (final queue in worker.queues) {
          if (queue.name.toLowerCase().contains(query)) return true;
        }
        return false;
      })
      .toList(growable: false);
}

List<QueueSummary> _searchQueues(List<QueueSummary> queues, String query) {
  if (query.isEmpty) return const [];
  return queues
      .where((queue) => queue.queue.toLowerCase().contains(query))
      .toList(growable: false);
}

List<DashboardAuditEntry> _searchAudit(
  List<DashboardAuditEntry> audits,
  String query,
) {
  if (query.isEmpty) return const [];
  return audits
      .where((entry) {
        if (entry.action.toLowerCase().contains(query)) return true;
        if (entry.summary?.toLowerCase().contains(query) ?? false) {
          return true;
        }
        if (entry.actor?.toLowerCase().contains(query) ?? false) return true;
        if (entry.status.toLowerCase().contains(query)) return true;
        for (final value in entry.metadata.values) {
          if (value?.toString().toLowerCase().contains(query) ?? false) {
            return true;
          }
        }
        return false;
      })
      .toList(growable: false);
}
