// Public helper functions in this file are intentionally undocumented to keep
// UI template files lightweight.
// ignore_for_file: public_member_api_docs

import 'package:stem_dashboard/src/services/models.dart';
import 'package:stem_dashboard/src/ui/options.dart';
import 'package:stem_dashboard/src/ui/shared.dart';

String buildWorkflowsContent({
  required List<DashboardTaskStatusEntry> taskStatuses,
  required WorkflowsPageOptions options,
}) {
  final runs = buildWorkflowRunSummaries(taskStatuses, limit: 400);
  final workflowFilter = options.workflow?.toLowerCase();
  final runFilter = options.runId?.toLowerCase();
  final filtered = runs.where((entry) {
    final matchesWorkflow =
        workflowFilter == null ||
        workflowFilter.isEmpty ||
        entry.workflowName.toLowerCase().contains(workflowFilter);
    final matchesRun =
        runFilter == null ||
        runFilter.isEmpty ||
        entry.runId.toLowerCase().contains(runFilter);
    return matchesWorkflow && matchesRun;
  }).toList(growable: false);

  final running = filtered.fold<int>(0, (sum, entry) => sum + entry.running);
  final failed = filtered.fold<int>(0, (sum, entry) => sum + entry.failed);
  final queued = filtered.fold<int>(0, (sum, entry) => sum + entry.queued);

  return '''
<section class="page-header rounded-2xl border border-slate-300/15 bg-slate-900/45 px-5 py-5">
  <h1>Workflows</h1>
  <p class="page-subtitle">
    Workflow run activity inferred from task metadata with run-level drill down.
  </p>
</section>

<section class="cards">
  ${buildMetricCard('Runs (sample)', formatInt(filtered.length), 'Distinct workflow run IDs currently visible in task status history.')}
  ${buildMetricCard('Queued steps', formatInt(queued), 'Queued or retried statuses across sampled runs.')}
  ${buildMetricCard('Running steps', formatInt(running), 'Statuses currently executing inside workflow runs.')}
  ${buildMetricCard('Failed steps', formatInt(failed), 'Failed statuses mapped to workflow runs.')}
</section>

<form class="filter-form rounded-2xl border border-slate-300/15 bg-slate-900/40 p-4" action="/workflows" method="get" data-turbo-frame="dashboard-content">
  <label class="filter-label" for="workflow-filter">Workflow name</label>
  <input id="workflow-filter" name="workflow" value="${escapeHtml(options.workflow ?? '')}" placeholder="greetingFlow" />
  <label class="filter-label" for="workflow-run-filter">Run ID</label>
  <input id="workflow-run-filter" name="runId" value="${escapeHtml(options.runId ?? '')}" placeholder="019c..." />
  <button type="submit">Apply</button>
  ${(options.hasWorkflow || options.hasRunId) ? '<a class="clear-filter" href="/workflows" data-turbo-frame="dashboard-content">Clear</a>' : ''}
</form>

<section class="table-card ring-1 ring-inset ring-sky-300/10">
  <header class="border-b border-slate-300/10 px-4 py-3">
    <h2 class="text-sm font-semibold uppercase tracking-wider text-slate-300">Workflow Runs</h2>
  </header>
  <table>
    <thead>
      <tr>
        <th scope="col">Run ID</th>
        <th scope="col">Workflow</th>
        <th scope="col">Last step</th>
        <th scope="col">Queued</th>
        <th scope="col">Running</th>
        <th scope="col">Succeeded</th>
        <th scope="col">Failed</th>
        <th scope="col">Cancelled</th>
        <th scope="col">Updated</th>
        <th scope="col">Actions</th>
      </tr>
    </thead>
    <tbody>
      ${filtered.isEmpty ? '''
<tr>
  <td colspan="10" class="muted">No workflow runs match the current filters.</td>
</tr>
''' : filtered.map((entry) => '''
<tr>
  <td><code>${escapeHtml(entry.runId)}</code></td>
  <td>${escapeHtml(entry.workflowName)}</td>
  <td class="muted">${escapeHtml(entry.lastStep ?? '—')}</td>
  <td>${formatInt(entry.queued)}</td>
  <td>${formatInt(entry.running)}</td>
  <td>${formatInt(entry.succeeded)}</td>
  <td>${formatInt(entry.failed)}</td>
  <td>${formatInt(entry.cancelled)}</td>
  <td class="muted">${formatRelative(entry.lastUpdated)}</td>
  <td>
    <div class="action-bar">
      <a class="ghost-button" href="/tasks/detail?runId=${Uri.encodeQueryComponent(entry.runId)}" data-turbo-frame="dashboard-content">Run Detail</a>
      <a class="ghost-button" href="/tasks?runId=${Uri.encodeQueryComponent(entry.runId)}" data-turbo-frame="dashboard-content">Tasks</a>
      <a class="ghost-button" href="/search?scope=tasks&q=${Uri.encodeQueryComponent(entry.runId)}" data-turbo-frame="dashboard-content">Search</a>
    </div>
  </td>
</tr>
''').join()}
    </tbody>
  </table>
</section>
''';
}
