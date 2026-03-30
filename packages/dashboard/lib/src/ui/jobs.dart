// Public helper functions in this file are intentionally undocumented to keep
// UI template files lightweight.
// ignore_for_file: public_member_api_docs

import 'package:stem_dashboard/src/services/models.dart';
import 'package:stem_dashboard/src/ui/options.dart';
import 'package:stem_dashboard/src/ui/shared.dart';

String buildJobsContent({
  required List<DashboardTaskStatusEntry> taskStatuses,
  required JobsPageOptions options,
}) {
  final jobs = buildJobSummaries(taskStatuses, limit: 500);
  final taskFilter = options.task?.toLowerCase();
  final queueFilter = options.queue?.toLowerCase();
  final filtered = jobs
      .where((entry) {
        final matchesTask =
            taskFilter == null ||
            taskFilter.isEmpty ||
            entry.taskName.toLowerCase().contains(taskFilter);
        final matchesQueue =
            queueFilter == null ||
            queueFilter.isEmpty ||
            entry.sampleQueue.toLowerCase().contains(queueFilter);
        return matchesTask && matchesQueue;
      })
      .toList(growable: false);

  final total = filtered.fold<int>(0, (sum, entry) => sum + entry.total);
  final running = filtered.fold<int>(0, (sum, entry) => sum + entry.running);
  final failures = filtered.fold<int>(0, (sum, entry) => sum + entry.failed);

  return '''
<section class="page-header rounded-2xl border border-slate-300/15 bg-slate-900/45 px-5 py-5">
  <h1>Jobs</h1>
  <p class="page-subtitle">
    Task family rollups with quick drill down into filtered task execution history.
  </p>
</section>

<section class="cards">
  ${buildMetricCard('Task families', formatInt(filtered.length), 'Distinct task names represented in sampled statuses.')}
  ${buildMetricCard('Sampled statuses', formatInt(total), 'Total status records currently included in this page sample.')}
  ${buildMetricCard('Running', formatInt(running), 'Running statuses across filtered task families.')}
  ${buildMetricCard('Failures', formatInt(failures), 'Failed statuses across filtered task families.')}
</section>

<form class="filter-form rounded-2xl border border-slate-300/15 bg-slate-900/40 p-4" action="/jobs" method="get" data-turbo-frame="dashboard-content">
  <label class="filter-label" for="job-task-filter">Task name</label>
  <input id="job-task-filter" name="task" value="${escapeHtml(options.task ?? '')}" placeholder="greeting.send" />
  <label class="filter-label" for="job-queue-filter">Queue</label>
  <input id="job-queue-filter" name="queue" value="${escapeHtml(options.queue ?? '')}" placeholder="default" />
  <button type="submit">Apply</button>
  ${(options.hasTask || options.hasQueue) ? '<a class="clear-filter" href="/jobs" data-turbo-frame="dashboard-content">Clear</a>' : ''}
</form>

<section class="table-card ring-1 ring-inset ring-sky-300/10">
  <header class="border-b border-slate-300/10 px-4 py-3">
    <h2 class="text-sm font-semibold uppercase tracking-wider text-slate-300">Job Summary</h2>
  </header>
  <table>
    <thead>
      <tr>
        <th scope="col">Task</th>
        <th scope="col">Queue</th>
        <th scope="col">Sampled</th>
        <th scope="col">Running</th>
        <th scope="col">Succeeded</th>
        <th scope="col">Failed</th>
        <th scope="col">Retried</th>
        <th scope="col">Cancelled</th>
        <th scope="col">Failure ratio</th>
        <th scope="col">Updated</th>
        <th scope="col">Actions</th>
      </tr>
    </thead>
    <tbody>
      ${filtered.isEmpty ? '''
<tr>
  <td colspan="11" class="muted">No jobs match the current filters.</td>
</tr>
''' : filtered.map((entry) => '''
<tr>
  <td>${escapeHtml(entry.taskName)}</td>
  <td><span class="pill">${escapeHtml(entry.sampleQueue)}</span></td>
  <td>${formatInt(entry.total)}</td>
  <td>${formatInt(entry.running)}</td>
  <td>${formatInt(entry.succeeded)}</td>
  <td>${formatInt(entry.failed)}</td>
  <td>${formatInt(entry.retried)}</td>
  <td>${formatInt(entry.cancelled)}</td>
  <td>${(entry.failureRatio * 100).toStringAsFixed(1)}%</td>
  <td class="muted">${formatRelative(entry.lastUpdated)}</td>
  <td>
    <div class="action-bar">
      <a class="ghost-button" href="/tasks?task=${Uri.encodeQueryComponent(entry.taskName)}" data-turbo-frame="dashboard-content">Tasks</a>
      <a class="ghost-button" href="/tasks?queue=${Uri.encodeQueryComponent(entry.sampleQueue)}&task=${Uri.encodeQueryComponent(entry.taskName)}" data-turbo-frame="dashboard-content">Queue Slice</a>
      <a class="ghost-button" href="/search?scope=tasks&q=${Uri.encodeQueryComponent(entry.taskName)}" data-turbo-frame="dashboard-content">Search</a>
    </div>
  </td>
</tr>
''').join()}
    </tbody>
  </table>
</section>
''';
}
