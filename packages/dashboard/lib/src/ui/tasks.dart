// HTML template strings are kept on single lines for readability.
// ignore_for_file: lines_longer_than_80_chars, public_member_api_docs

import 'package:stem_dashboard/src/services/models.dart';
import 'package:stem_dashboard/src/ui/options.dart';
import 'package:stem_dashboard/src/ui/shared.dart';

String buildTasksContent(List<QueueSummary> queues, TasksPageOptions options) {
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

  return '''
<section class="page-header">
  <h1>Tasks</h1>
  <p class="page-subtitle">
    Queue depth, inflight counts, and dead letter insight. Replay controls arrive alongside Turbo stream actions.
  </p>
</section>

${renderTasksAlert(options)}

<section class="cards">
  ${buildMetricCard('Tracked queues', formatInt(totalQueues), 'Queues discovered via Redis stream prefixes.')}
  ${buildMetricCard('Dead letter size', formatInt(dlqTotal), 'Aggregate items across all dead letter queues.')}
</section>

<form class="filter-form" action="/tasks" method="get" data-turbo-frame="dashboard-content">
  <label class="filter-label" for="queue-filter">Queue filter</label>
  <input id="queue-filter" name="queue" value="${escapeHtml(options.filter ?? '')}" placeholder="default" />
  <input type="hidden" name="sort" value="${options.sortKey}" />
  <input type="hidden" name="direction" value="${options.descending ? 'desc' : 'asc'}" />
  <button type="submit">Apply</button>
  ${options.hasFilter ? '<a class="clear-filter" href="/tasks" data-turbo-frame="dashboard-content">Clear</a>' : ''}
</form>

<section class="table-card">
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

<section class="event-feed" style="margin-top: 28px;">
  <div class="enqueue-card">
    <h3>Ad-hoc enqueue</h3>
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
  };
  if (options.hasFilter) {
    params['queue'] = options.filter!;
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
