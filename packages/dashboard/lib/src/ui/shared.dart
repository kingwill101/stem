import 'package:intl/intl.dart';
import 'package:stem/stem.dart' show TaskState, stemNow;
// Public helper functions in this file are intentionally undocumented to keep
// UI template files lightweight.
// ignore_for_file: public_member_api_docs

import 'package:stem_dashboard/src/services/models.dart';

final dashboardNumberFormat = NumberFormat.decimalPattern();

String buildQueueTableRow(QueueSummary summary) {
  final escapedQueue = escapeHtml(summary.queue);
  return '''
<tr class="queue-row group" data-queue-row="$escapedQueue">
  <td><span class="pill">$escapedQueue</span></td>
  <td class="font-medium text-slate-100">${formatInt(summary.pending)}</td>
  <td class="font-medium text-slate-100">${formatInt(summary.inflight)}</td>
  <td class="font-medium text-slate-100">${formatInt(summary.deadLetters)}</td>
</tr>
<tr class="queue-detail" data-queue-detail="$escapedQueue">
  <td colspan="4" class="bg-slate-950/40">
    <div class="detail-grid">
      <div><span class="muted">Pending</span> ${formatInt(summary.pending)}</div>
      <div><span class="muted">In-flight</span> ${formatInt(summary.inflight)}</div>
      <div><span class="muted">Dead letters</span> ${formatInt(summary.deadLetters)}</div>
      <div class="muted">Detailed DLQ previews render here once the replay control is wired.</div>
    </div>
  </td>
</tr>
''';
}

String buildMetricCard(String title, String value, String caption) {
  return '''
<article class="card relative overflow-hidden">
  <div class="pointer-events-none absolute -right-8 -top-10 h-24 w-24 rounded-full bg-sky-300/10 blur-2xl"></div>
  <div class="card-title">$title</div>
  <div class="card-value text-slate-100">$value</div>
  <p class="card-caption">$caption</p>
</article>
''';
}

String buildEmptyQueuesRow(String message) {
  return '''
<tr>
  <td colspan="4" class="muted py-8 text-center">$message</td>
</tr>
''';
}

String escapeHtml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

int totalIsolates(List<WorkerStatus> workers) {
  return workers.fold<int>(0, (total, status) => total + status.isolateCount);
}

String formatInt(int value) => dashboardNumberFormat.format(value);

String formatRate(double value) {
  if (value <= 0) return '0';
  if (value < 1) return value.toStringAsFixed(2);
  return dashboardNumberFormat.format(value.round());
}

String formatRelative(DateTime timestamp) {
  final now = stemNow().toUtc();
  final diff = now.difference(timestamp.toUtc());
  if (diff < const Duration(seconds: 30)) return 'just now';
  if (diff < const Duration(minutes: 1)) {
    return '${diff.inSeconds}s ago';
  }
  if (diff < const Duration(hours: 1)) {
    return '${diff.inMinutes}m ago';
  }
  if (diff < const Duration(days: 1)) {
    return '${diff.inHours}h ago';
  }
  return '${diff.inDays}d ago';
}

String formatDateTime(DateTime? timestamp) {
  if (timestamp == null) return '—';
  return timestamp.toUtc().toIso8601String();
}

String formatObject(Object? value) {
  if (value == null) return 'null';
  if (value is String) return value;
  return value.toString();
}

String taskStateLabel(TaskState state) {
  switch (state) {
    case TaskState.queued:
      return 'Queued';
    case TaskState.running:
      return 'Running';
    case TaskState.succeeded:
      return 'Succeeded';
    case TaskState.failed:
      return 'Failed';
    case TaskState.retried:
      return 'Retried';
    case TaskState.cancelled:
      return 'Cancelled';
  }
}

String taskStateClass(TaskState state) {
  switch (state) {
    case TaskState.succeeded:
      return 'success';
    case TaskState.failed:
      return 'error';
    case TaskState.cancelled:
      return 'error';
    case TaskState.running:
      return 'running';
    case TaskState.retried:
      return 'warning';
    case TaskState.queued:
      return 'muted';
  }
}

String buildTaskStatePill(TaskState state) {
  return '<span class="pill ${taskStateClass(state)} font-semibold uppercase tracking-wide">${taskStateLabel(state)}</span>';
}

class DashboardTaskTableOptions {
  const DashboardTaskTableOptions({
    this.showState = true,
    this.showAttempt = true,
    this.showUpdated = true,
    this.showError = true,
    this.showActions = true,
    this.expandableRows = false,
    this.emptyMessage = 'No task statuses available.',
    this.actionsBuilder,
  });

  final bool showState;
  final bool showAttempt;
  final bool showUpdated;
  final bool showError;
  final bool showActions;
  final bool expandableRows;
  final String emptyMessage;
  final String Function(DashboardTaskStatusEntry task)? actionsBuilder;
}

String buildTaskStatusTable(
  List<DashboardTaskStatusEntry> tasks, {
  required DashboardTaskTableOptions options,
}) {
  final headers = <String>[
    'Task ID',
    'Task',
    'Queue',
    if (options.showState) 'State',
    if (options.showAttempt) 'Attempt',
    if (options.showUpdated) 'Updated',
    if (options.showError) 'Error',
    if (options.showActions) 'Actions',
  ];

  final rows = tasks.isEmpty
      ? '''
<tr>
  <td colspan="${headers.length}" class="muted">${escapeHtml(options.emptyMessage)}</td>
</tr>
'''
      : tasks.map((task) => _buildTaskStatusRow(task, options: options)).join();

  return '''
<table>
  <thead>
    <tr>
      ${headers.map((header) => '<th scope="col">$header</th>').join()}
    </tr>
  </thead>
  <tbody>
    $rows
  </tbody>
</table>
''';
}

String buildTaskLifecycleActions(
  DashboardTaskStatusEntry task, {
  required String redirectPath,
}) {
  final encodedId = escapeHtml(task.id);
  final encodedQueue = escapeHtml(task.queue);
  final encodedRedirect = escapeHtml(redirectPath);
  final controls = <String>[];

  if (task.state == TaskState.running || task.state == TaskState.queued) {
    controls.add('''
<form class="inline-form" action="/tasks/action" method="post" data-turbo-frame="dashboard-content">
  <input type="hidden" name="action" value="cancel" />
  <input type="hidden" name="taskId" value="$encodedId" />
  <input type="hidden" name="queue" value="$encodedQueue" />
  <input type="hidden" name="redirect" value="$encodedRedirect" />
  <button type="submit" class="ghost-button">Cancel</button>
</form>
''');
  }

  if (task.state == TaskState.failed || task.state == TaskState.cancelled) {
    controls.add('''
<form class="inline-form" action="/tasks/action" method="post" data-turbo-frame="dashboard-content">
  <input type="hidden" name="action" value="replay" />
  <input type="hidden" name="taskId" value="$encodedId" />
  <input type="hidden" name="queue" value="$encodedQueue" />
  <input type="hidden" name="redirect" value="$encodedRedirect" />
  <button type="submit" class="ghost-button">Replay</button>
</form>
''');
  }

  if (controls.isEmpty) {
    return '<span class="muted">—</span>';
  }
  return '<div class="action-bar">${controls.join()}</div>';
}

String buildTaskReplayAction(
  DashboardTaskStatusEntry task, {
  required String redirectPath,
  String label = 'Replay task',
}) {
  return '''
<form class="inline-form" action="/tasks/action" method="post" data-turbo-frame="dashboard-content">
  <input type="hidden" name="action" value="replay" />
  <input type="hidden" name="taskId" value="${escapeHtml(task.id)}" />
  <input type="hidden" name="queue" value="${escapeHtml(task.queue)}" />
  <input type="hidden" name="redirect" value="${escapeHtml(redirectPath)}" />
  <button type="submit" class="ghost-button">${escapeHtml(label)}</button>
</form>
''';
}

String _buildTaskStatusRow(
  DashboardTaskStatusEntry task, {
  required DashboardTaskTableOptions options,
}) {
  final escapedId = escapeHtml(task.id);
  final detailUrl = '/tasks/detail?id=${Uri.encodeQueryComponent(task.id)}';
  final inlineTarget = 'task-inline-$escapedId';
  final rowClass = options.expandableRows ? 'task-row' : '';
  final rowAttrs = options.expandableRows
      ? ' data-task-row="$escapedId" '
            'data-task-inline-target="$inlineTarget" aria-expanded="false"'
      : '';

  return '''
<tr class="$rowClass"$rowAttrs>
  <td class="whitespace-nowrap"><a class="font-semibold text-sky-200 hover:text-sky-100" href="$detailUrl" data-turbo-frame="dashboard-content"><code>$escapedId</code></a></td>
  <td class="whitespace-nowrap">${escapeHtml(task.taskName)}</td>
  <td class="whitespace-nowrap"><span class="pill">${escapeHtml(task.queue)}</span></td>
  ${options.showState ? '<td class="whitespace-nowrap">${buildTaskStatePill(task.state)}</td>' : ''}
  ${options.showAttempt ? '<td class="whitespace-nowrap">${formatInt(task.attempt)}</td>' : ''}
  ${options.showUpdated ? '<td class="muted whitespace-nowrap">${formatRelative(task.updatedAt)}</td>' : ''}
  ${options.showError ? '<td class="muted"><span class="error-preview" title="${escapeHtml(task.errorMessage ?? (task.retryable ? 'retryable' : '—'))}">${escapeHtml(_compactError(task))}</span></td>' : ''}
  ${options.showActions ? '<td class="whitespace-nowrap">${options.actionsBuilder?.call(task) ?? '<span class="muted">—</span>'}</td>' : ''}
</tr>
''';
}

String _compactError(DashboardTaskStatusEntry task, {int max = 120}) {
  final raw = task.errorMessage ?? (task.retryable ? 'retryable' : '—');
  final singleLine = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  return _truncate(singleLine, max);
}

String _truncate(String input, int max) {
  if (input.length <= max) return input;
  return '${input.substring(0, max - 1)}…';
}
