// Public helper functions in this file are intentionally undocumented to keep
// UI template files lightweight.
// ignore_for_file: public_member_api_docs

import 'package:stem_dashboard/src/services/models.dart';
import 'package:stem_dashboard/src/ui/options.dart';
import 'package:stem_dashboard/src/ui/shared.dart';

String buildNamespacesContent({
  required List<QueueSummary> queues,
  required List<WorkerStatus> workers,
  required List<DashboardTaskStatusEntry> taskStatuses,
  required NamespacesPageOptions options,
  required String defaultNamespace,
}) {
  final snapshots = buildNamespaceSnapshots(
    queues: queues,
    workers: workers,
    tasks: taskStatuses,
    defaultNamespace: defaultNamespace,
  );
  final namespaceFilter = options.namespace?.toLowerCase();
  final filtered = options.hasNamespace
      ? snapshots
            .where(
              (entry) =>
                  entry.namespace.toLowerCase().contains(namespaceFilter!),
            )
            .toList(growable: false)
      : snapshots;

  final totalPending = filtered.fold<int>(
    0,
    (sum, entry) => sum + entry.pending,
  );
  final totalInflight = filtered.fold<int>(
    0,
    (sum, entry) => sum + entry.inflight,
  );
  final totalFailed = filtered.fold<int>(
    0,
    (sum, entry) => sum + entry.failedTasks,
  );

  return '''
<section class="page-header rounded-2xl border border-slate-300/15 bg-slate-900/45 px-5 py-5">
  <h1>Namespaces</h1>
  <p class="page-subtitle">
    App-scoped health grouped by namespace with drill-down controls into tasks and workers.
  </p>
</section>

<section class="cards">
  ${buildMetricCard('Namespaces', formatInt(filtered.length), 'Distinct namespaces detected from queue, worker, and task metadata.')}
  ${buildMetricCard('Backlog', formatInt(totalPending), 'Pending envelopes across selected namespaces.')}
  ${buildMetricCard('In-flight', formatInt(totalInflight), 'Current processing load across selected namespaces.')}
  ${buildMetricCard('Failed tasks', formatInt(totalFailed), 'Recent terminal failures observed for selected namespaces.')}
</section>

<form class="filter-form rounded-2xl border border-slate-300/15 bg-slate-900/40 p-4" action="/namespaces" method="get" data-turbo-frame="dashboard-content">
  <label class="filter-label" for="namespace-filter">Namespace</label>
  <input id="namespace-filter" name="namespace" value="${escapeHtml(options.namespace ?? '')}" placeholder="stem" />
  <button type="submit">Apply</button>
  ${options.hasNamespace ? '<a class="clear-filter" href="/namespaces" data-turbo-frame="dashboard-content">Clear</a>' : ''}
</form>

<section class="table-card ring-1 ring-inset ring-sky-300/10">
  <header class="border-b border-slate-300/10 px-4 py-3">
    <h2 class="text-sm font-semibold uppercase tracking-wider text-slate-300">Namespace Summary</h2>
  </header>
  <table>
    <thead>
      <tr>
        <th scope="col">Namespace</th>
        <th scope="col">Queues</th>
        <th scope="col">Workers</th>
        <th scope="col">Backlog</th>
        <th scope="col">In-flight</th>
        <th scope="col">Dead letters</th>
        <th scope="col">Running</th>
        <th scope="col">Failed</th>
        <th scope="col">Workflow runs</th>
        <th scope="col">Actions</th>
      </tr>
    </thead>
    <tbody>
      ${filtered.isEmpty ? '''
<tr>
  <td colspan="10" class="muted">No namespace data matches the current filter.</td>
</tr>
''' : filtered.map((entry) => '''
<tr>
  <td><span class="pill">${escapeHtml(entry.namespace)}</span></td>
  <td>${formatInt(entry.queueCount)}</td>
  <td>${formatInt(entry.workerCount)}</td>
  <td>${formatInt(entry.pending)}</td>
  <td>${formatInt(entry.inflight)}</td>
  <td>${formatInt(entry.deadLetters)}</td>
  <td>${formatInt(entry.runningTasks)}</td>
  <td>${formatInt(entry.failedTasks)}</td>
  <td>${formatInt(entry.workflowRuns)}</td>
  <td>
    <div class="action-bar">
      <a class="ghost-button" href="/tasks?namespace=${Uri.encodeQueryComponent(entry.namespace)}" data-turbo-frame="dashboard-content">Tasks</a>
      <a class="ghost-button" href="/workers?namespace=${Uri.encodeQueryComponent(entry.namespace)}" data-turbo-frame="dashboard-content">Workers</a>
      <a class="ghost-button" href="/search?scope=tasks&q=${Uri.encodeQueryComponent(entry.namespace)}" data-turbo-frame="dashboard-content">Search</a>
    </div>
  </td>
</tr>
''').join()}
    </tbody>
  </table>
</section>
''';
}
