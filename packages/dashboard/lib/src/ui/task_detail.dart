// Public helper functions in this file are intentionally undocumented to keep
// UI template files lightweight.
// ignore_for_file: public_member_api_docs

import 'dart:convert';

import 'package:stem/stem.dart' show TaskState;
import 'package:stem_dashboard/src/services/models.dart';
import 'package:stem_dashboard/src/ui/shared.dart';

String buildTaskDetailContent(
  DashboardTaskStatusEntry? task,
  List<DashboardTaskStatusEntry> runTimeline,
  DashboardWorkflowRunSnapshot? workflowRun,
  List<DashboardWorkflowStepSnapshot> workflowSteps,
) {
  if (task == null) {
    return '''
<section class="page-header rounded-2xl border border-slate-300/15 bg-slate-900/45 px-5 py-5">
  <h1>Task Detail</h1>
  <p class="page-subtitle">Task status record was not found in the current result backend window.</p>
</section>
<section class="event-feed">
  <div class="event-item ring-1 ring-inset ring-red-300/20">
    <h3 class="text-lg font-semibold text-slate-100">Task not found</h3>
    <p class="muted">Try searching from the tasks page again.</p>
    <p><a href="/tasks" class="ghost-button" data-turbo-frame="dashboard-content">Back to tasks</a></p>
  </div>
</section>
''';
  }

  final timeline = List<DashboardTaskStatusEntry>.from(runTimeline)
    ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
  final metadataEntries = task.meta.entries.toList(growable: false)
    ..sort((a, b) => a.key.compareTo(b.key));

  return '''
<section class="page-header rounded-2xl border border-slate-300/15 bg-slate-900/45 px-5 py-5">
  <h1>Task Detail</h1>
  <p class="page-subtitle">
    Inspect lifecycle history, workflow linkage, and payload/error details for a single task status.
  </p>
</section>

<section class="cards">
  ${buildMetricCard('Task', escapeHtml(task.taskName), 'Handler name reported by task status metadata.')}
  ${buildMetricCard('Queue', escapeHtml(task.queue), 'Queue where this task executed.')}
  ${buildMetricCard('State', escapeHtml(task.state.name), 'Current persisted state.')}
  ${buildMetricCard('Attempt', formatInt(task.attempt), 'Attempt count stored on the latest status write.')}
</section>

<section class="control-panel ring-1 ring-inset ring-sky-300/10">
  <h2 class="section-heading">Task actions</h2>
  <div class="action-bar">
    ${buildTaskActions(task)}
  </div>
</section>

<section class="table-card ring-1 ring-inset ring-sky-300/10">
  <header class="border-b border-slate-300/10 px-4 py-3">
    <h2 class="text-sm font-semibold uppercase tracking-wider text-slate-300">Task Snapshot</h2>
  </header>
  <table>
    <tbody>
      <tr><th scope="row">Task ID</th><td><code>${escapeHtml(task.id)}</code></td></tr>
      <tr><th scope="row">Created</th><td class="muted">${formatDateTime(task.createdAt)}</td></tr>
      <tr><th scope="row">Updated</th><td class="muted">${formatDateTime(task.updatedAt)}</td></tr>
      <tr><th scope="row">Run ID</th><td>${task.runId == null ? '<span class="muted">—</span>' : '<a href="/tasks/detail?id=${Uri.encodeQueryComponent(task.id)}&runId=${Uri.encodeQueryComponent(task.runId!)}" data-turbo-frame="dashboard-content"><code>${escapeHtml(task.runId!)}</code></a>'}</td></tr>
      <tr><th scope="row">Workflow</th><td>${task.workflowName == null ? '<span class="muted">—</span>' : escapeHtml(task.workflowName!)}</td></tr>
      <tr><th scope="row">Workflow Step</th><td>${task.workflowStep == null ? '<span class="muted">—</span>' : escapeHtml(task.workflowStep!)}</td></tr>
    </tbody>
  </table>
</section>

<section class="table-card mt-7 p-4 ring-1 ring-inset ring-sky-300/10">
  <h2 class="section-heading">Payload / Error</h2>
  <div class="detail-grid">
    <div>
      <div class="muted">Payload</div>
      <pre class="payload-block">${escapeHtml(_prettyObject(task.payload))}</pre>
    </div>
    <div>
      <div class="muted">Error</div>
      <pre class="payload-block">${escapeHtml(_errorBlock(task))}</pre>
    </div>
  </div>
</section>

<section class="table-card mt-7 ring-1 ring-inset ring-sky-300/10">
  <header class="border-b border-slate-300/10 px-4 py-3">
    <h2 class="text-sm font-semibold uppercase tracking-wider text-slate-300">Metadata</h2>
  </header>
  <table>
    <thead>
      <tr>
        <th scope="col">Metadata key</th>
        <th scope="col">Value</th>
      </tr>
    </thead>
    <tbody>
      ${metadataEntries.isEmpty ? '''
<tr>
  <td colspan="2" class="muted">No metadata fields persisted for this status.</td>
</tr>
''' : metadataEntries.map((entry) => '''
<tr>
  <td><code>${escapeHtml(entry.key)}</code></td>
  <td class="muted">${escapeHtml(_prettyObject(entry.value))}</td>
</tr>
''').join()}
    </tbody>
  </table>
</section>

${buildWorkflowSection(task, workflowRun, workflowSteps, timeline)}
''';
}

String buildWorkflowSection(
  DashboardTaskStatusEntry task,
  DashboardWorkflowRunSnapshot? workflowRun,
  List<DashboardWorkflowStepSnapshot> workflowSteps,
  List<DashboardTaskStatusEntry> timeline,
) {
  if (task.runId == null) {
    return '''
<section class="event-feed mt-7">
  <div class="event-item ring-1 ring-inset ring-sky-300/10">
    <h3 class="text-lg font-semibold text-slate-100">No workflow linkage</h3>
    <p class="muted">This task status does not include <code>stem.workflow.runId</code> metadata.</p>
  </div>
</section>
''';
  }

  final runId = task.runId!;
  return '''
<section class="table-card mt-7 ring-1 ring-inset ring-sky-300/10">
  <header class="border-b border-slate-300/10 px-4 py-3">
    <h2 class="text-sm font-semibold uppercase tracking-wider text-slate-300">Workflow Run</h2>
  </header>
  <table>
    <thead>
      <tr>
        <th scope="col">Workflow run</th>
        <th scope="col">Status</th>
        <th scope="col">Cursor</th>
        <th scope="col">Updated</th>
        <th scope="col">Wait topic</th>
      </tr>
    </thead>
    <tbody>
      ${workflowRun == null ? '''
<tr>
  <td colspan="5" class="muted">Workflow store is unavailable or this run is no longer persisted.</td>
</tr>
''' : '''
<tr>
  <td><code>${escapeHtml(runId)}</code></td>
  <td><span class="pill">${escapeHtml(workflowRun.status.name)}</span></td>
  <td>${formatInt(workflowRun.cursor)}</td>
  <td class="muted">${formatDateTime(workflowRun.updatedAt)}</td>
  <td class="muted">${escapeHtml(workflowRun.waitTopic ?? '—')}</td>
</tr>
'''}
    </tbody>
  </table>
</section>

<section class="table-card mt-7 ring-1 ring-inset ring-sky-300/10">
  <header class="border-b border-slate-300/10 px-4 py-3">
    <h2 class="text-sm font-semibold uppercase tracking-wider text-slate-300">Workflow Checkpoints</h2>
  </header>
  <table>
    <thead>
      <tr>
        <th scope="col">Checkpoint</th>
        <th scope="col">Position</th>
        <th scope="col">Completed</th>
        <th scope="col">Value</th>
      </tr>
    </thead>
    <tbody>
      ${workflowSteps.isEmpty ? '''
<tr>
  <td colspan="4" class="muted">No persisted workflow step checkpoints found.</td>
</tr>
''' : workflowSteps.map((step) => '''
<tr>
  <td>${escapeHtml(step.name)}</td>
  <td>${formatInt(step.position)}</td>
  <td class="muted">${formatDateTime(step.completedAt)}</td>
  <td class="muted">${escapeHtml(_prettyObject(step.value))}</td>
</tr>
''').join()}
    </tbody>
  </table>
</section>

<section class="table-card mt-7 ring-1 ring-inset ring-sky-300/10">
  <header class="border-b border-slate-300/10 px-4 py-3">
    <h2 class="text-sm font-semibold uppercase tracking-wider text-slate-300">Run Timeline</h2>
  </header>
  <table>
    <thead>
      <tr>
        <th scope="col">Task ID</th>
        <th scope="col">Task</th>
        <th scope="col">Step</th>
        <th scope="col">State</th>
        <th scope="col">Attempt</th>
        <th scope="col">Updated</th>
      </tr>
    </thead>
    <tbody>
      ${timeline.isEmpty ? '''
<tr>
  <td colspan="6" class="muted">No related statuses were found for run <code>${escapeHtml(runId)}</code>.</td>
</tr>
''' : timeline.map((entry) => '''
<tr>
  <td><a href="/tasks/detail?id=${Uri.encodeQueryComponent(entry.id)}" data-turbo-frame="dashboard-content"><code>${escapeHtml(entry.id)}</code></a></td>
  <td>${escapeHtml(entry.taskName)}</td>
  <td>${escapeHtml(entry.workflowStep ?? '—')}</td>
  <td>${buildTaskStatePill(entry.state)}</td>
  <td>${formatInt(entry.attempt)}</td>
  <td class="muted">${formatRelative(entry.updatedAt)}</td>
</tr>
''').join()}
    </tbody>
  </table>
</section>
''';
}

String _prettyObject(Object? value) {
  if (value == null) return 'null';
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } on Object {
    return value.toString();
  }
}

String _errorBlock(DashboardTaskStatusEntry task) {
  if (task.errorMessage == null &&
      task.errorType == null &&
      task.errorStack == null) {
    return 'No error payload recorded.';
  }
  final buffer = StringBuffer();
  if (task.errorType != null && task.errorType!.isNotEmpty) {
    buffer.writeln(task.errorType);
  }
  if (task.errorMessage != null && task.errorMessage!.isNotEmpty) {
    buffer.writeln(task.errorMessage);
  }
  if (task.errorStack != null && task.errorStack!.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln(task.errorStack);
  }
  return buffer.toString().trim();
}

String buildTaskActions(DashboardTaskStatusEntry task) {
  final redirect = '/tasks/detail?id=${Uri.encodeQueryComponent(task.id)}';
  final encodedId = escapeHtml(task.id);
  final encodedQueue = escapeHtml(task.queue);
  final actions = <String>[];

  if (task.state == TaskState.running || task.state == TaskState.queued) {
    actions.add('''
<form class="inline-form" action="/tasks/action" method="post" data-turbo-frame="dashboard-content">
  <input type="hidden" name="action" value="cancel" />
  <input type="hidden" name="taskId" value="$encodedId" />
  <input type="hidden" name="queue" value="$encodedQueue" />
  <input type="hidden" name="redirect" value="$redirect" />
  <button type="submit" class="ghost-button">Cancel task</button>
</form>
''');
  }

  if (task.state == TaskState.failed || task.state == TaskState.cancelled) {
    actions.add('''
<form class="inline-form" action="/tasks/action" method="post" data-turbo-frame="dashboard-content">
  <input type="hidden" name="action" value="replay" />
  <input type="hidden" name="taskId" value="$encodedId" />
  <input type="hidden" name="queue" value="$encodedQueue" />
  <input type="hidden" name="redirect" value="$redirect" />
  <button type="submit" class="ghost-button">Replay from DLQ</button>
</form>
''');
  }

  actions.add(
    '<a href="/tasks" data-turbo-frame="dashboard-content" class="ghost-button">Back to tasks</a>',
  );
  return actions.join();
}
