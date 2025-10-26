import 'package:intl/intl.dart';

import '../services/models.dart';
import 'event_templates.dart';
import 'layout.dart';

final _numberFormat = NumberFormat.decimalPattern();

class TasksPageOptions {
  const TasksPageOptions({
    this.sortKey = 'queue',
    this.descending = false,
    this.filter,
    this.flashKey,
    this.errorKey,
  });

  final String sortKey;
  final bool descending;
  final String? filter;
  final String? flashKey;
  final String? errorKey;

  bool get hasFilter => filter != null && filter!.isNotEmpty;
}

class WorkersPageOptions {
  const WorkersPageOptions({this.flashMessage, this.errorMessage, this.scope});

  final String? flashMessage;
  final String? errorMessage;
  final String? scope;

  bool get hasFlash => flashMessage != null && flashMessage!.isNotEmpty;
  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;
  bool get hasScope => scope != null && scope!.isNotEmpty;
}

String buildPageContent({
  required DashboardPage page,
  required List<QueueSummary> queues,
  required List<WorkerStatus> workers,
  List<DashboardEvent> events = const [],
  TasksPageOptions tasksOptions = const TasksPageOptions(),
  WorkersPageOptions workersOptions = const WorkersPageOptions(),
}) {
  switch (page) {
    case DashboardPage.overview:
      return _overviewContent(queues, workers);
    case DashboardPage.tasks:
      return _tasksContent(queues, tasksOptions);
    case DashboardPage.events:
      return _eventsContent(events);
    case DashboardPage.workers:
      return _workersContent(workers, queues, workersOptions);
  }
}

String _overviewContent(List<QueueSummary> queues, List<WorkerStatus> workers) {
  final totalPending = queues.fold<int>(
    0,
    (total, summary) => total + summary.pending,
  );
  final totalInflight = queues.fold<int>(
    0,
    (total, summary) => total + summary.inflight,
  );
  final totalDead = queues.fold<int>(
    0,
    (total, summary) => total + summary.deadLetters,
  );
  final activeWorkers = workers.length;
  final busiest = List<QueueSummary>.of(
    queues,
  )..sort((a, b) => (b.pending + b.inflight).compareTo(a.pending + a.inflight));
  final topQueues = busiest.take(5).toList();

  return '''
<section class="page-header">
  <h1>Overview</h1>
  <p class="page-subtitle">
    Live snapshot of Stem throughput and worker health. Metrics refresh with every navigation and Turbo frame update.
  </p>
</section>

<section class="cards">
  ${_metricCard('Queued', _formatInt(totalPending), 'Total tasks waiting across all queues.')}
  ${_metricCard('Processing', _formatInt(totalInflight), 'Active envelopes currently being executed.')}
  ${_metricCard('Dead letters', _formatInt(totalDead), 'Items held in dead letter queues.')}
  ${_metricCard('Active workers', _formatInt(activeWorkers), 'Workers that published heartbeats within the retention window.')}
</section>

<section class="table-card">
  <table>
    <thead>
      <tr>
        <th scope="col">Queue</th>
        <th scope="col">Pending</th>
        <th scope="col">In-flight</th>
        <th scope="col">Dead letters</th>
      </tr>
    </thead>
    <tbody>
      ${topQueues.isEmpty ? _emptyQueuesRow('No queues detected yet.') : topQueues.map(_queueTableRow).join()}
    </tbody>
  </table>
</section>
''';
}

String _tasksContent(List<QueueSummary> queues, TasksPageOptions options) {
  var filtered = options.hasFilter
      ? queues
            .where(
              (summary) => summary.queue.toLowerCase().contains(
                options.filter!.toLowerCase(),
              ),
            )
            .toList()
      : List<QueueSummary>.of(queues);

  filtered.sort((a, b) => _compareQueues(a, b, options));
  if (options.descending) {
    filtered = filtered.reversed.toList();
  }

  final totalQueues = filtered.length;
  final dlqTotal = filtered.fold<int>(
    0,
    (total, summary) => total + summary.deadLetters,
  );

  return '''
<section class="page-header">
  <h1>Tasks</h1>
  <p class="page-subtitle">
    Queue depth, inflight counts, and dead letter insight. Replay controls arrive alongside Turbo stream actions.
  </p>
</section>

${_renderTasksAlert(options)}

<section class="cards">
  ${_metricCard('Tracked queues', _formatInt(totalQueues), 'Queues discovered via Redis stream prefixes.')}
  ${_metricCard('Dead letter size', _formatInt(dlqTotal), 'Aggregate items across all dead letter queues.')}
</section>

<form class="filter-form" action="/tasks" method="get" data-turbo-frame="dashboard-content">
  <label class="filter-label" for="queue-filter">Queue filter</label>
  <input id="queue-filter" name="queue" value="${_escapeHtml(options.filter ?? '')}" placeholder="default" />
  <input type="hidden" name="sort" value="${options.sortKey}" />
  <input type="hidden" name="direction" value="${options.descending ? 'desc' : 'asc'}" />
  <button type="submit">Apply</button>
  ${options.hasFilter ? '<a class="clear-filter" href="/tasks" data-turbo-frame="dashboard-content">Clear</a>' : ''}
</form>

<section class="table-card">
  <table>
    <thead>
      <tr>
        <th scope="col">${_sortableHeader('Queue', 'queue', options)}</th>
        <th scope="col">${_sortableHeader('Pending', 'pending', options)}</th>
        <th scope="col">${_sortableHeader('In-flight', 'inflight', options)}</th>
        <th scope="col">${_sortableHeader('Dead letters', 'dead', options)}</th>
      </tr>
    </thead>
    <tbody>
      ${filtered.isEmpty ? _emptyQueuesRow('No streams found for the configured namespace.') : filtered.map(_queueTableRow).join()}
    </tbody>
  </table>
</section>

<section class="event-feed" style="margin-top: 28px;">
  <div class="enqueue-card">
    <h3>Ad-hoc enqueue</h3>
    <form class="enqueue-form" action="/tasks/enqueue" method="post" data-turbo-frame="dashboard-content">
      <div class="form-grid">
        <label>
          Queue
          <input name="queue" value="${_escapeHtml(options.filter ?? '')}" placeholder="default" required />
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

String _eventsContent(List<DashboardEvent> events) {
  final items = events.isEmpty
      ? '''
        <div class="event-item" id="event-log-placeholder">
          <h3>No events captured yet</h3>
          <p class="muted">
            Configure the dashboard event bridge to stream Stem signals (enqueue, start, retry, completion) into Redis.
            Once connected, updates will appear here automatically via Turbo Streams.
          </p>
        </div>
      '''
      : events.map(renderEventItem).join();

  return '''
<section class="page-header">
  <h1>Events</h1>
  <p class="page-subtitle">
    Task lifecycle, retry, and worker log events stream into this feed. Turbo handles incremental updates without full-page reloads.
  </p>
</section>

<section class="event-feed" id="event-log">
  $items
</section>
''';
}

String _workersContent(
  List<WorkerStatus> workers,
  List<QueueSummary> queues,
  WorkersPageOptions options,
) {
  final healthyWorkers = workers.where((worker) {
    return worker.age <= const Duration(minutes: 2);
  }).length;

  final busy = workers.where((worker) => worker.inflight > 0).length;
  final queueMap = {for (final summary in queues) summary.queue: summary};

  return '''
<section class="page-header">
  <h1>Workers</h1>
  <p class="page-subtitle">
    Heartbeat health, queue assignments, and in-flight counts. Issue control plane commands and replay dead letters inline.
  </p>
</section>

${_renderWorkersAlert(options)}

<section class="cards">
  ${_metricCard('Healthy workers', _formatInt(healthyWorkers), 'Heartbeats received within the last two minutes.')}
  ${_metricCard('Busy workers', _formatInt(busy), 'Workers currently processing at least one task.')}
  ${_metricCard('Isolates in use', _formatInt(_totalIsolates(workers)), 'Sum of worker isolates across the cluster.')}
</section>

<section class="table-card">
  <table>
    <thead>
      <tr>
        <th scope="col">Worker</th>
        <th scope="col">Queues</th>
        <th scope="col">Inflight</th>
        <th scope="col">Last heartbeat</th>
        <th scope="col">Actions</th>
      </tr>
    </thead>
    <tbody>
      ${workers.isEmpty ? '''
              <tr>
                <td colspan="5" class="muted">No heartbeats detected for namespace "${workers.isEmpty ? 'stem' : workers.first.namespace}".</td>
              </tr>
            ''' : workers.map(_workerRow).join()}
    </tbody>
  </table>
</section>

${_clusterControls()}

${_queueRecoverySection(queueMap)}
''';
}

String _queueTableRow(QueueSummary summary) {
  return '''
<tr class="queue-row" data-queue-row="${summary.queue}">
  <td><span class="pill">${summary.queue}</span></td>
  <td>${_formatInt(summary.pending)}</td>
  <td>${_formatInt(summary.inflight)}</td>
  <td>${_formatInt(summary.deadLetters)}</td>
</tr>
<tr class="queue-detail" data-queue-detail="${summary.queue}">
  <td colspan="4">
    <div class="detail-grid">
      <div><span class="muted">Pending</span> ${_formatInt(summary.pending)}</div>
      <div><span class="muted">In-flight</span> ${_formatInt(summary.inflight)}</div>
      <div><span class="muted">Dead letters</span> ${_formatInt(summary.deadLetters)}</div>
      <div class="muted">Detailed DLQ previews render here once the replay control is wired.</div>
    </div>
  </td>
</tr>
''';
}

String _workerRow(WorkerStatus status) {
  final queues = status.queues.isEmpty
      ? '<span class="muted">—</span>'
      : status.queues
            .map((queue) => '<span class="pill">${queue.name}</span>')
            .join(' ');
  return '''
<tr>
  <td>${status.workerId}</td>
  <td>$queues</td>
  <td>${_formatInt(status.inflight)}</td>
  <td class="muted">${_formatRelative(status.timestamp)}</td>
  <td>
    <div class="action-bar">
      ${_workerActionButton('Ping', 'ping', status.workerId)}
      ${_workerActionButton('Pause', 'pause', status.workerId)}
      ${_workerActionButton('Shutdown', 'shutdown', status.workerId)}
    </div>
  </td>
</tr>
''';
}

String _workerActionButton(String label, String action, String workerId) {
  return '''
<form class="inline-form" action="/workers/control" method="post" data-turbo-frame="dashboard-content">
  <input type="hidden" name="worker" value="${_escapeHtml(workerId)}" />
  <input type="hidden" name="action" value="${_escapeHtml(action)}" />
  <button type="submit" class="ghost-button">$label</button>
</form>
''';
}

String _clusterControls() {
  return '''
<section class="control-panel">
  <h2 class="section-heading">Cluster controls</h2>
  <div class="action-bar">
    ${_clusterActionButton('Ping all workers', 'ping')}
    ${_clusterActionButton('Pause all workers', 'pause')}
    ${_clusterActionButton('Shutdown all workers', 'shutdown')}
  </div>
</section>
''';
}

String _clusterActionButton(String label, String action) {
  return '''
<form class="inline-form" action="/workers/control" method="post" data-turbo-frame="dashboard-content">
  <input type="hidden" name="worker" value="*" />
  <input type="hidden" name="action" value="${_escapeHtml(action)}" />
  <button type="submit" class="ghost-button">$label</button>
</form>
''';
}

String _queueRecoverySection(Map<String, QueueSummary> queues) {
  if (queues.isEmpty) return '';
  final rows = queues.values.toList()
    ..sort((a, b) => a.queue.compareTo(b.queue));
  return '''
<section class="table-card" style="margin-top: 28px;">
  <table>
    <thead>
      <tr>
        <th scope="col">Queue</th>
        <th scope="col">Pending</th>
        <th scope="col">Dead letters</th>
        <th scope="col">Replay</th>
      </tr>
    </thead>
    <tbody>
      ${rows.map(_queueRecoveryRow).join()}
    </tbody>
  </table>
</section>
''';
}

String _queueRecoveryRow(QueueSummary summary) {
  final limitDefault = summary.deadLetters <= 0
      ? 50
      : summary.deadLetters.clamp(1, 50).toInt();
  final action = summary.deadLetters == 0
      ? '<span class="muted">No dead letters</span>'
      : '''
      <form class="inline-form" action="/queues/replay" method="post" data-turbo-frame="dashboard-content">
        <input type="hidden" name="queue" value="${_escapeHtml(summary.queue)}" />
        <input type="hidden" name="limit" value="$limitDefault" />
        <button type="submit" class="ghost-button">Replay</button>
      </form>
    ''';
  return '''
<tr>
  <td><span class="pill">${_escapeHtml(summary.queue)}</span></td>
  <td>${_formatInt(summary.pending)}</td>
  <td>${_formatInt(summary.deadLetters)}</td>
  <td>$action</td>
</tr>
''';
}

String _metricCard(String title, String value, String caption) {
  return '''
<article class="card">
  <div class="card-title">$title</div>
  <div class="card-value">$value</div>
  <p class="card-caption">$caption</p>
</article>
''';
}

String _emptyQueuesRow(String message) {
  return '''
<tr>
  <td colspan="4" class="muted">$message</td>
</tr>
''';
}

String _renderTasksAlert(TasksPageOptions options) {
  String? message;
  String type = 'success';
  switch (options.flashKey) {
    case 'queued':
      message = 'Task enqueued successfully.';
      break;
  }
  switch (options.errorKey) {
    case 'missing-fields':
      message = 'Queue and task name are required.';
      type = 'error';
      break;
    case 'invalid-payload':
      message = 'Payload must be valid JSON describing an object.';
      type = 'error';
      break;
    case 'enqueue-failed':
      message =
          'Failed to enqueue the task. Check the dashboard logs for details.';
      type = 'error';
      break;
  }

  if (message == null) return '';
  return '<div class="flash $type">${_escapeHtml(message)}</div>';
}

String _renderWorkersAlert(WorkersPageOptions options) {
  if (options.hasError) {
    final scope = options.hasScope
        ? '<div class="muted">Target: ${_escapeHtml(options.scope!)}.</div>'
        : '';
    return '''
<div class="flash error">
  ${_escapeHtml(options.errorMessage!)}
  $scope
</div>
''';
  }
  if (options.hasFlash) {
    final scope = options.hasScope
        ? '<div class="muted">Target: ${_escapeHtml(options.scope!)}.</div>'
        : '';
    return '''
<div class="flash success">
  ${_escapeHtml(options.flashMessage!)}
  $scope
</div>
''';
  }
  return '';
}

int _compareQueues(QueueSummary a, QueueSummary b, TasksPageOptions options) {
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

String _sortableHeader(String label, String key, TasksPageOptions options) {
  final isActive = options.sortKey == key;
  final descendingNext = isActive ? !options.descending : key != 'queue';
  final params = <String, String>{
    'sort': key,
    'direction': descendingNext ? 'desc' : 'asc',
  };
  if (options.hasFilter) {
    params['queue'] = options.filter!;
  }
  final query = _buildQuery(params);
  final indicator = isActive ? (options.descending ? '&darr;' : '&uarr;') : '';
  final classes = isActive ? 'sort-link active' : 'sort-link';
  return '<a class="$classes" href="/tasks?$query" data-turbo-frame="dashboard-content">$label $indicator</a>';
}

String _buildQuery(Map<String, String> params) {
  return params.entries
      .map(
        (entry) =>
            '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
      )
      .join('&');
}

String _escapeHtml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

int _totalIsolates(List<WorkerStatus> workers) {
  return workers.fold<int>(0, (total, status) => total + status.isolateCount);
}

String _formatInt(int value) => _numberFormat.format(value);

String _formatRelative(DateTime timestamp) {
  final now = DateTime.now().toUtc();
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
