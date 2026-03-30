// Public helper functions in this file are intentionally undocumented to keep
// UI template files lightweight.
// ignore_for_file: public_member_api_docs

import 'package:stem/stem.dart' show TaskState;
import 'package:stem_dashboard/src/services/models.dart';
import 'package:stem_dashboard/src/ui/options.dart';
import 'package:stem_dashboard/src/ui/shared.dart';

String buildFailuresContent(
  List<DashboardTaskStatusEntry> taskStatuses,
  FailuresPageOptions options,
) {
  final failures = taskStatuses
      .where((task) => task.state == TaskState.failed)
      .toList(growable: false);
  final filtered = options.hasQueueFilter
      ? failures
            .where(
              (task) =>
                  task.queue.toLowerCase() == options.queue!.toLowerCase(),
            )
            .toList(growable: false)
      : failures;

  final groups = _groupFailures(filtered)
    ..sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      if (byCount != 0) return byCount;
      return b.lastUpdated.compareTo(a.lastUpdated);
    });

  final affectedQueues = filtered.map((task) => task.queue).toSet().length;
  final redirectPath = options.hasQueueFilter
      ? '/failures?queue=${Uri.encodeQueryComponent(options.queue!)}'
      : '/failures';

  return '''
<section class="page-header rounded-2xl border border-slate-300/15 bg-slate-900/45 px-5 py-5">
  <h1>Failure Diagnostics</h1>
  <p class="page-subtitle">
    Grouped failure fingerprints across queues and tasks with direct dead-letter replay controls.
  </p>
</section>

${renderFailuresAlert(options)}

<section class="cards">
  ${buildMetricCard('Failed statuses', formatInt(filtered.length), 'Terminal failed task statuses captured by the result backend.')}
  ${buildMetricCard('Failure groups', formatInt(groups.length), 'Unique queue + task + error fingerprints.')}
  ${buildMetricCard('Affected queues', formatInt(affectedQueues), 'Queues currently carrying failed statuses.')}
</section>

<form class="filter-form rounded-2xl border border-slate-300/15 bg-slate-900/40 p-4" action="/failures" method="get" data-turbo-frame="dashboard-content">
  <label class="filter-label" for="failure-queue-filter">Queue filter</label>
  <input id="failure-queue-filter" name="queue" value="${escapeHtml(options.queue ?? '')}" placeholder="default" />
  <button type="submit">Apply</button>
  ${options.hasQueueFilter ? '<a class="clear-filter" href="/failures" data-turbo-frame="dashboard-content">Clear</a>' : ''}
</form>

<section class="table-card ring-1 ring-inset ring-sky-300/10">
  <header class="border-b border-slate-300/10 px-4 py-3">
    <h2 class="text-sm font-semibold uppercase tracking-wider text-slate-300">Failure Groups</h2>
  </header>
  <table>
    <thead>
      <tr>
        <th scope="col">Queue</th>
        <th scope="col">Task</th>
        <th scope="col">Fingerprint</th>
        <th scope="col">Count</th>
        <th scope="col">Latest</th>
        <th scope="col">Retry</th>
      </tr>
    </thead>
    <tbody>
      ${groups.isEmpty ? '''
<tr>
  <td colspan="6" class="muted">No failed statuses match the current filter.</td>
</tr>
''' : groups.map((group) => '''
<tr>
  <td><span class="pill">${escapeHtml(group.queue)}</span></td>
  <td>${escapeHtml(group.taskName)}</td>
  <td class="muted">${escapeHtml(group.errorFingerprint)}</td>
  <td>${formatInt(group.count)}</td>
  <td class="muted">${formatRelative(group.lastUpdated)}</td>
  <td>
    <form class="inline-form" action="/queues/replay" method="post" data-turbo-frame="dashboard-content">
      <input type="hidden" name="queue" value="${escapeHtml(group.queue)}" />
      <input type="hidden" name="limit" value="${group.replayLimit}" />
      <input type="hidden" name="redirect" value="${escapeHtml(redirectPath)}" />
      <button type="submit" class="ghost-button">Replay DLQ</button>
    </form>
  </td>
</tr>
''').join()}
    </tbody>
  </table>
</section>

<section class="table-card mt-7 ring-1 ring-inset ring-sky-300/10">
  <header class="border-b border-slate-300/10 px-4 py-3">
    <h2 class="text-sm font-semibold uppercase tracking-wider text-slate-300">Recent Failed Tasks</h2>
  </header>
  ${buildTaskStatusTable(
    filtered.take(40).toList(growable: false),
    options: DashboardTaskTableOptions(
      showState: false,
      emptyMessage: 'No individual failures to inspect.',
      actionsBuilder: (task) => buildTaskReplayAction(task, redirectPath: redirectPath),
    ),
  )}
</section>
''';
}

String renderFailuresAlert(FailuresPageOptions options) {
  if (options.hasError) {
    return '<div class="flash error">${escapeHtml(options.errorMessage!)}</div>';
  }
  if (options.hasFlash) {
    return '<div class="flash success">${escapeHtml(options.flashMessage!)}</div>';
  }
  return '';
}

List<_FailureGroup> _groupFailures(List<DashboardTaskStatusEntry> statuses) {
  final groups = <String, _FailureGroup>{};
  for (final task in statuses) {
    final key = '${task.queue}|${task.taskName}|${task.errorFingerprint}';
    final existing = groups[key];
    if (existing == null) {
      groups[key] = _FailureGroup(
        queue: task.queue,
        taskName: task.taskName,
        errorFingerprint: task.errorFingerprint,
        count: 1,
        lastUpdated: task.updatedAt,
      );
      continue;
    }
    groups[key] = existing.copyWith(
      count: existing.count + 1,
      lastUpdated: task.updatedAt.isAfter(existing.lastUpdated)
          ? task.updatedAt
          : existing.lastUpdated,
    );
  }
  return groups.values.toList(growable: false);
}

class _FailureGroup {
  const _FailureGroup({
    required this.queue,
    required this.taskName,
    required this.errorFingerprint,
    required this.count,
    required this.lastUpdated,
  });

  final String queue;
  final String taskName;
  final String errorFingerprint;
  final int count;
  final DateTime lastUpdated;

  int get replayLimit => count.clamp(1, 100);

  _FailureGroup copyWith({int? count, DateTime? lastUpdated}) {
    return _FailureGroup(
      queue: queue,
      taskName: taskName,
      errorFingerprint: errorFingerprint,
      count: count ?? this.count,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}
