// HTML template strings are kept on single lines for readability.
// ignore_for_file: lines_longer_than_80_chars, public_member_api_docs

import 'dart:convert';

import 'package:stem/stem.dart' show TaskState, stemNow;
import 'package:stem_dashboard/src/services/models.dart';
import 'package:stem_dashboard/src/ui/options.dart';
import 'package:stem_dashboard/src/ui/shared.dart';

String buildTasksContent(
  List<QueueSummary> queues,
  TasksPageOptions options,
  List<DashboardTaskStatusEntry> taskStatuses,
) {
  var filtered =
      options.hasFilter
            ? queues
                  .where(
                    (summary) => summary.queue.toLowerCase().contains(
                      options.filter!.toLowerCase(),
                    ),
                  )
                  .toList()
            : List<QueueSummary>.of(queues)
        ..sort((a, b) => compareQueues(a, b, options));
  if (options.descending) {
    filtered = filtered.reversed.toList();
  }

  final totalQueues = filtered.length;
  final dlqTotal = filtered.fold<int>(
    0,
    (total, summary) => total + summary.deadLetters,
  );
  final runningCount = taskStatuses
      .where((task) => task.state == TaskState.running)
      .length;
  final failedCount = taskStatuses
      .where((task) => task.state == TaskState.failed)
      .length;
  final retriedCount = taskStatuses
      .where((task) => task.state == TaskState.retried)
      .length;
  final now = stemNow().toUtc();
  const queuedStuckThreshold = Duration(minutes: 5);
  const runningStuckThreshold = Duration(minutes: 15);
  final stuckQueued = taskStatuses
      .where((task) {
        if (task.state != TaskState.queued) return false;
        return now.difference(task.createdAt.toUtc()) > queuedStuckThreshold;
      })
      .toList(growable: false);
  final stuckRunning = taskStatuses
      .where((task) {
        if (task.state != TaskState.running) return false;
        final anchor = task.startedAt ?? task.updatedAt.toUtc();
        return now.difference(anchor) > runningStuckThreshold;
      })
      .toList(growable: false);
  final queueLatency = _buildQueueLatency(taskStatuses);
  final slaBreaches = queueLatency.fold<int>(
    0,
    (total, item) => total + item.slaBreaches,
  );
  final taskActionRedirect = _buildTasksRedirect(options);

  return '''
<section class="page-header rounded-2xl border border-slate-300/15 bg-slate-900/45 px-5 py-5">
  <h1>Tasks</h1>
  <p class="page-subtitle">
    Queue depth, inflight counts, and dead letter insight. Replay controls arrive alongside Turbo stream actions.
  </p>
</section>

${renderTasksAlert(options)}

<section class="cards">
  ${buildMetricCard('Tracked queues', formatInt(totalQueues), 'Queues discovered via Redis stream prefixes.')}
  ${buildMetricCard('Dead letter size', formatInt(dlqTotal), 'Aggregate items across all dead letter queues.')}
  ${buildMetricCard('Running tasks', formatInt(runningCount), 'Recent statuses currently processing.')}
  ${buildMetricCard('Failed tasks', formatInt(failedCount), 'Recent statuses with terminal failures.')}
  ${buildMetricCard('Retried tasks', formatInt(retriedCount), 'Recent statuses scheduled for another attempt.')}
  ${buildMetricCard('Stuck queued', formatInt(stuckQueued.length), 'Queued beyond ${queuedStuckThreshold.inMinutes}m from initial status creation.')}
  ${buildMetricCard('Stuck running', formatInt(stuckRunning.length), 'Running beyond ${runningStuckThreshold.inMinutes}m from start heartbeat metadata.')}
  ${buildMetricCard('SLA breaches', formatInt(slaBreaches), 'Queue wait > 1m or processing > 5m across sampled statuses.')}
</section>

<form class="filter-form rounded-2xl border border-slate-300/15 bg-slate-900/40 p-4" action="/tasks" method="get" data-turbo-frame="dashboard-content">
  <label class="filter-label" for="queue-filter">Queue filter</label>
  <input id="queue-filter" name="queue" value="${escapeHtml(options.filter ?? '')}" placeholder="default" />
  <label class="filter-label" for="namespace-filter">Namespace</label>
  <input id="namespace-filter" name="namespace" value="${escapeHtml(options.namespaceFilter ?? '')}" placeholder="stem" />
  <label class="filter-label" for="task-filter">Task name</label>
  <input id="task-filter" name="task" value="${escapeHtml(options.taskFilter ?? '')}" placeholder="greeting.send" />
  <label class="filter-label" for="run-filter">Run ID</label>
  <input id="run-filter" name="runId" value="${escapeHtml(options.runId ?? '')}" placeholder="019c..." />
  <label class="filter-label" for="state-filter">Task state</label>
  ${buildTaskStateFilterSelect(options)}
  <label class="filter-label" for="page-size">Page size</label>
  ${buildTaskPageSizeSelect(options)}
  <input type="hidden" name="sort" value="${options.sortKey}" />
  <input type="hidden" name="direction" value="${options.descending ? 'desc' : 'asc'}" />
  <input type="hidden" name="page" value="1" />
  <button type="submit">Apply</button>
  ${(options.hasFilter || options.hasNamespaceFilter || options.hasTaskFilter || options.hasRunIdFilter) ? '<a class="clear-filter" href="/tasks" data-turbo-frame="dashboard-content">Clear</a>' : ''}
</form>

<section class="table-card ring-1 ring-inset ring-sky-300/10">
  <header class="border-b border-slate-300/10 px-4 py-3">
    <h2 class="text-sm font-semibold uppercase tracking-wider text-slate-300">Queue Snapshot</h2>
  </header>
  <table>
    <thead>
      <tr>
        <th scope="col">${buildSortableHeader('Queue', 'queue', options)}</th>
        <th scope="col">${buildSortableHeader('Pending', 'pending', options)}</th>
        <th scope="col">${buildSortableHeader('In-flight', 'inflight', options)}</th>
        <th scope="col">${buildSortableHeader('Dead letters', 'dead', options)}</th>
      </tr>
    </thead>
    <tbody>
      ${filtered.isEmpty ? buildEmptyQueuesRow('No streams found for the configured namespace.') : filtered.map(buildQueueTableRow).join()}
    </tbody>
  </table>
</section>

<section class="table-card mt-7 ring-1 ring-inset ring-sky-300/10">
  <header class="border-b border-slate-300/10 px-4 py-3">
    <h2 class="text-sm font-semibold uppercase tracking-wider text-slate-300">Latency Watch</h2>
  </header>
  <table>
    <thead>
      <tr>
        <th scope="col">Queue</th>
        <th scope="col">Samples</th>
        <th scope="col">Wait avg</th>
        <th scope="col">Wait p95</th>
        <th scope="col">Run avg</th>
        <th scope="col">Run p95</th>
        <th scope="col">SLA breaches</th>
      </tr>
    </thead>
    <tbody>
      ${queueLatency.isEmpty ? '''
<tr>
  <td colspan="7" class="muted">No latency samples yet. Task metadata must include started/completed timestamps.</td>
</tr>
''' : queueLatency.map((latency) => '''
<tr>
  <td><span class="pill">${escapeHtml(latency.queue)}</span></td>
  <td>${formatInt(latency.samples)}</td>
  <td>${latency.avgWaitLabel}</td>
  <td>${latency.p95WaitLabel}</td>
  <td>${latency.avgRunLabel}</td>
  <td>${latency.p95RunLabel}</td>
  <td>${formatInt(latency.slaBreaches)}</td>
</tr>
''').join()}
    </tbody>
  </table>
</section>

<section class="table-card mt-7 ring-1 ring-inset ring-sky-300/10">
  <header class="border-b border-slate-300/10 px-4 py-3">
    <h2 class="text-sm font-semibold uppercase tracking-wider text-slate-300">Recent Statuses</h2>
  </header>
  ${buildTaskPaginationBar(options, taskStatuses.length)}
  ${buildTaskStatusTable(
    taskStatuses,
    options: DashboardTaskTableOptions(
      emptyMessage: 'No task statuses match the current filters.',
      expandableRows: true,
      actionsBuilder: (task) => buildTaskLifecycleActions(task, redirectPath: taskActionRedirect),
    ),
  )}
  ${buildTaskPaginationBar(options, taskStatuses.length)}
</section>

<section class="event-feed mt-7">
  <div class="enqueue-card ring-1 ring-inset ring-sky-300/10">
    <h3 class="mb-3 text-lg font-semibold tracking-tight text-slate-100">Ad-hoc enqueue</h3>
    <form class="enqueue-form" action="/tasks/enqueue" method="post" data-turbo-frame="dashboard-content">
      <div class="form-grid">
        <label>
          Queue
          <input name="queue" value="${escapeHtml(options.filter ?? '')}" placeholder="default" required />
        </label>
        <label>
          Task name
          <input name="task" placeholder="example.send_email" required />
        </label>
        <label>
          Priority
          <input name="priority" type="number" min="0" max="9" value="0" />
        </label>
        <label>
          Max retries
          <input name="maxRetries" type="number" min="0" value="0" />
        </label>
        <label class="payload-label">
          Payload (JSON object)
          <textarea name="payload" rows="4" placeholder='{"userId":123}'></textarea>
        </label>
      </div>
      <button type="submit">Queue Task</button>
    </form>
  </div>
</section>
''';
}

String renderTasksAlert(TasksPageOptions options) {
  String? message;
  var type = 'success';
  switch (options.flashKey) {
    case 'queued':
      message = 'Task enqueued successfully.';
    default:
      message = options.flashKey;
  }
  switch (options.errorKey) {
    case 'missing-fields':
      message = 'Queue and task name are required.';
      type = 'error';
    case 'invalid-payload':
      message = 'Payload must be valid JSON describing an object.';
      type = 'error';
    case 'enqueue-failed':
      message =
          'Failed to enqueue the task. Check the dashboard logs for details.';
      type = 'error';
    default:
      if (options.errorKey != null && options.errorKey!.isNotEmpty) {
        message = options.errorKey;
        type = 'error';
      }
  }

  if (message == null) return '';
  return '<div class="flash $type">${escapeHtml(message)}</div>';
}

int compareQueues(QueueSummary a, QueueSummary b, TasksPageOptions options) {
  switch (options.sortKey) {
    case 'pending':
      return a.pending.compareTo(b.pending);
    case 'inflight':
      return a.inflight.compareTo(b.inflight);
    case 'dead':
      return a.deadLetters.compareTo(b.deadLetters);
    case 'queue':
    default:
      return a.queue.toLowerCase().compareTo(b.queue.toLowerCase());
  }
}

String buildSortableHeader(String label, String key, TasksPageOptions options) {
  final isActive = options.sortKey == key;
  final descendingNext = isActive ? !options.descending : key != 'queue';
  final params = <String, String>{
    'sort': key,
    'direction': descendingNext ? 'desc' : 'asc',
    'page': '1',
    'pageSize': '${options.pageSize}',
  };
  if (options.hasFilter) {
    params['queue'] = options.filter!;
  }
  if (options.hasNamespaceFilter) {
    params['namespace'] = options.namespaceFilter!;
  }
  if (options.hasTaskFilter) {
    params['task'] = options.taskFilter!;
  }
  if (options.hasRunIdFilter) {
    params['runId'] = options.runId!;
  }
  if (options.hasStateFilter) {
    params['state'] = options.stateFilter!.name;
  }
  final query = buildQuery(params);
  final indicator = isActive ? (options.descending ? '&darr;' : '&uarr;') : '';
  final classes = isActive ? 'sort-link active' : 'sort-link';
  return '<a class="$classes" href="/tasks?$query" data-turbo-frame="dashboard-content">$label $indicator</a>';
}

String buildQuery(Map<String, String> params) {
  return params.entries
      .map(
        (entry) =>
            '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
      )
      .join('&');
}

String buildTaskStateFilterSelect(TasksPageOptions options) {
  final current = options.stateFilter?.name;
  String option(TaskState? state, String label) {
    final value = state?.name ?? '';
    final selected = current == value ? ' selected' : '';
    return '<option value="$value"$selected>$label</option>';
  }

  return '''
<select id="state-filter" name="state">
  ${option(null, 'Any')}
  ${option(TaskState.queued, 'Queued')}
  ${option(TaskState.running, 'Running')}
  ${option(TaskState.succeeded, 'Succeeded')}
  ${option(TaskState.failed, 'Failed')}
  ${option(TaskState.retried, 'Retried')}
  ${option(TaskState.cancelled, 'Cancelled')}
</select>
''';
}

String buildTaskPageSizeSelect(TasksPageOptions options) {
  const sizes = [25, 50, 100, 200];
  final normalized = sizes.contains(options.pageSize) ? options.pageSize : 25;
  final optionsHtml = sizes.map((size) {
    final selected = normalized == size ? ' selected' : '';
    return '<option value="$size"$selected>$size</option>';
  }).join();
  return '<select id="page-size" name="pageSize">$optionsHtml</select>';
}

String buildTaskPaginationBar(TasksPageOptions options, int rowsOnPage) {
  if (!options.hasPagination) {
    return '';
  }
  final start = rowsOnPage == 0 ? 0 : options.offset + 1;
  final end = options.offset + rowsOnPage;
  final baseParams = <String, String>{
    'sort': options.sortKey,
    'direction': options.descending ? 'desc' : 'asc',
    'pageSize': '${options.pageSize}',
  };
  if (options.hasFilter) {
    baseParams['queue'] = options.filter!;
  }
  if (options.hasNamespaceFilter) {
    baseParams['namespace'] = options.namespaceFilter!;
  }
  if (options.hasTaskFilter) {
    baseParams['task'] = options.taskFilter!;
  }
  if (options.hasRunIdFilter) {
    baseParams['runId'] = options.runId!;
  }
  if (options.hasStateFilter) {
    baseParams['state'] = options.stateFilter!.name;
  }

  final previousLink = options.hasPreviousPage
      ? '<a class="ghost-button" href="/tasks?${buildQuery({...baseParams, 'page': '${options.page - 1}'})}" data-turbo-frame="dashboard-content">Previous</a>'
      : '<span class="ghost-button disabled">Previous</span>';
  final nextLink = options.hasNextPage
      ? '<a class="ghost-button" href="/tasks?${buildQuery({...baseParams, 'page': '${options.page + 1}'})}" data-turbo-frame="dashboard-content">Next</a>'
      : '<span class="ghost-button disabled">Next</span>';

  return '''
<div class="pager">
  <span class="muted">Page ${options.page} • Showing $start-$end</span>
  <div class="action-bar">
    $previousLink
    $nextLink
  </div>
</div>
''';
}

String _buildTasksRedirect(TasksPageOptions options) {
  final params = <String, String>{};
  if (options.hasFilter) {
    params['queue'] = options.filter!;
  }
  if (options.hasNamespaceFilter) {
    params['namespace'] = options.namespaceFilter!;
  }
  if (options.hasTaskFilter) {
    params['task'] = options.taskFilter!;
  }
  if (options.hasRunIdFilter) {
    params['runId'] = options.runId!;
  }
  if (options.hasStateFilter) {
    params['state'] = options.stateFilter!.name;
  }
  if (params.isEmpty) return '/tasks';
  return '/tasks?${buildQuery(params)}';
}

String buildTaskInlinePanel(DashboardTaskStatusEntry? task) {
  if (task == null) {
    return '''
<div class="event-item p-4">
  <p class="muted">Task detail could not be loaded from the result backend.</p>
</div>
''';
  }

  final detailUrl = '/tasks/detail?id=${Uri.encodeQueryComponent(task.id)}';
  final metadataEntries = task.meta.entries.toList(growable: false)
    ..sort((a, b) => a.key.compareTo(b.key));
  final metadataPreview = metadataEntries.isEmpty
      ? '<span class="muted">No metadata fields were persisted.</span>'
      : '<div class="meta-list">${metadataEntries.take(8).map((entry) => '''
<div class="meta-item">
  <code>${escapeHtml(entry.key)}</code>
  <span class="muted">${escapeHtml(_compactObject(entry.value))}</span>
</div>
''').join()}</div>${metadataEntries.length > 8 ? '<p class="muted">+${metadataEntries.length - 8} more metadata fields in full detail view.</p>' : ''}';
  final payloadPreview = escapeHtml(_compactObject(task.payload, max: 480));
  final errorPreview = escapeHtml(_buildErrorPreview(task));
  final workflowSummary = task.runId == null
      ? '<span class="muted">No workflow linkage</span>'
      : '<span><code>${escapeHtml(task.runId!)}</code>${task.workflowStep == null ? '' : ' · ${escapeHtml(task.workflowStep!)}'}</span>';

  return '''
<div class="detail-grid">
  <div>
    <div class="muted">Timestamps</div>
    <div>Created: ${escapeHtml(formatDateTime(task.createdAt))}</div>
    <div>Started: ${escapeHtml(formatDateTime(task.startedAt))}</div>
    <div>Finished: ${escapeHtml(formatDateTime(task.finishedAt))}</div>
  </div>
  <div>
    <div class="muted">Workflow</div>
    <div>$workflowSummary</div>
    <div class="muted">Updated ${escapeHtml(formatRelative(task.updatedAt))}</div>
  </div>
  <div>
    <div class="muted">Error snapshot</div>
    <pre class="payload-block">$errorPreview</pre>
  </div>
  <div>
    <div class="muted">Payload snapshot</div>
    <pre class="payload-block">$payloadPreview</pre>
  </div>
</div>
<div class="mt-3">
  <div class="muted mb-2">Metadata</div>
  $metadataPreview
</div>
<div class="action-bar mt-3">
  <a href="$detailUrl" data-turbo-frame="dashboard-content" class="ghost-button">Open full detail</a>
</div>
''';
}

String _buildErrorPreview(DashboardTaskStatusEntry task) {
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
    final stack = _truncate(task.errorStack!, 360);
    if (stack.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(stack);
    }
  }
  return buffer.toString().trim();
}

String _compactObject(Object? value, {int max = 180}) {
  final pretty = _prettyObject(value).replaceAll('\n', ' ');
  return _truncate(pretty, max);
}

String _truncate(String input, int max) {
  if (input.length <= max) return input;
  return '${input.substring(0, max)}...';
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

List<_QueueLatencyRow> _buildQueueLatency(
  List<DashboardTaskStatusEntry> tasks,
) {
  final byQueue = <String, _QueueLatencyAccumulator>{};
  const queueSla = Duration(minutes: 1);
  const runSla = Duration(minutes: 5);

  for (final task in tasks) {
    final bucket = byQueue.putIfAbsent(
      task.queue,
      () => _QueueLatencyAccumulator(queue: task.queue),
    );
    final wait = task.queueWait;
    final run = task.processingTime;
    bucket.add(wait: wait, run: run, queueSla: queueSla, runSla: runSla);
  }

  final rows =
      byQueue.values.map((value) => value.build()).toList(growable: false)
        ..sort((a, b) => b.slaBreaches.compareTo(a.slaBreaches));
  return rows;
}

class _QueueLatencyAccumulator {
  _QueueLatencyAccumulator({required this.queue});

  final String queue;
  final _waitSamples = <int>[];
  final _runSamples = <int>[];
  var _samples = 0;
  var _breaches = 0;

  void add({
    required Duration? wait,
    required Duration? run,
    required Duration queueSla,
    required Duration runSla,
  }) {
    _samples += 1;
    if (wait != null) {
      _waitSamples.add(wait.inMilliseconds);
      if (wait > queueSla) _breaches += 1;
    }
    if (run != null) {
      _runSamples.add(run.inMilliseconds);
      if (run > runSla) _breaches += 1;
    }
  }

  _QueueLatencyRow build() {
    return _QueueLatencyRow(
      queue: queue,
      samples: _samples,
      avgWaitMs: _average(_waitSamples),
      p95WaitMs: _percentile(_waitSamples, 0.95),
      avgRunMs: _average(_runSamples),
      p95RunMs: _percentile(_runSamples, 0.95),
      slaBreaches: _breaches,
    );
  }

  int _average(List<int> values) {
    if (values.isEmpty) return 0;
    final total = values.fold<int>(0, (sum, value) => sum + value);
    return (total / values.length).round();
  }

  int _percentile(List<int> values, double p) {
    if (values.isEmpty) return 0;
    final sorted = List<int>.from(values)..sort();
    final index = ((sorted.length - 1) * p).round().clamp(0, sorted.length - 1);
    return sorted[index];
  }
}

class _QueueLatencyRow {
  const _QueueLatencyRow({
    required this.queue,
    required this.samples,
    required this.avgWaitMs,
    required this.p95WaitMs,
    required this.avgRunMs,
    required this.p95RunMs,
    required this.slaBreaches,
  });

  final String queue;
  final int samples;
  final int avgWaitMs;
  final int p95WaitMs;
  final int avgRunMs;
  final int p95RunMs;
  final int slaBreaches;

  String get avgWaitLabel => _formatMs(avgWaitMs);
  String get p95WaitLabel => _formatMs(p95WaitMs);
  String get avgRunLabel => _formatMs(avgRunMs);
  String get p95RunLabel => _formatMs(p95RunMs);

  String _formatMs(int millis) {
    if (millis <= 0) return '—';
    if (millis < 1000) return '${millis}ms';
    return '${(millis / 1000).toStringAsFixed(2)}s';
  }
}
