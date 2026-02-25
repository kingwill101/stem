// Public helper functions in this file are intentionally undocumented to keep
// UI template files lightweight.
// ignore_for_file: public_member_api_docs

import 'package:stem/stem.dart' show TaskState, stemNow;
import 'package:stem_dashboard/src/services/models.dart';
import 'package:stem_dashboard/src/ui/shared.dart';

class OverviewSections {
  const OverviewSections({
    required this.metrics,
    required this.namespaces,
    required this.topQueues,
    required this.workflows,
    required this.jobs,
    required this.latency,
    required this.recentTasks,
  });

  final String metrics;
  final String namespaces;
  final String topQueues;
  final String workflows;
  final String jobs;
  final String latency;
  final String recentTasks;
}

String buildOverviewContent(
  List<QueueSummary> queues,
  List<WorkerStatus> workers,
  DashboardThroughput? throughput,
  List<DashboardTaskStatusEntry> taskStatuses,
  String defaultNamespace,
) {
  final sections = buildOverviewSections(
    queues,
    workers,
    throughput,
    taskStatuses,
    defaultNamespace: defaultNamespace,
  );
  return '''
<section class="page-header rounded-2xl border border-slate-300/15 bg-slate-900/45 px-5 py-5">
  <h1>Overview</h1>
  <p class="page-subtitle">
    Live snapshot of Stem throughput and worker health. Metrics refresh with every navigation and Turbo frame update.
  </p>
</section>

${sections.metrics}

${sections.namespaces}

${sections.topQueues}

${sections.workflows}

${sections.jobs}

${sections.latency}

${sections.recentTasks}
''';
}

OverviewSections buildOverviewSections(
  List<QueueSummary> queues,
  List<WorkerStatus> workers,
  DashboardThroughput? throughput,
  List<DashboardTaskStatusEntry> taskStatuses,
  {
    String defaultNamespace = 'stem',
  }
) {
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

  final processedPerMin = throughput?.processedPerMinute ?? 0;
  final enqueuedPerMin = throughput?.enqueuedPerMinute ?? 0;
  final failedTasks = taskStatuses.where(
    (task) => task.state == TaskState.failed,
  );
  final workflowTasks = taskStatuses.where((task) => task.isWorkflowTask);
  final runningTasks = taskStatuses.where(
    (task) => task.state == TaskState.running,
  );
  final now = stemNow().toUtc();
  const queuedStuckThreshold = Duration(minutes: 5);
  const runningStuckThreshold = Duration(minutes: 15);
  final stuckQueued = taskStatuses.where((task) {
    if (task.state != TaskState.queued) return false;
    return now.difference(task.createdAt.toUtc()) > queuedStuckThreshold;
  }).length;
  final stuckRunning = taskStatuses.where((task) {
    if (task.state != TaskState.running) return false;
    final anchor = task.startedAt ?? task.updatedAt.toUtc();
    return now.difference(anchor) > runningStuckThreshold;
  }).length;
  final queueLatency = _buildQueueLatency(taskStatuses);
  final namespaces = buildNamespaceSnapshots(
    queues: queues,
    workers: workers,
    tasks: taskStatuses,
    defaultNamespace: defaultNamespace,
  );
  final workflowRuns = buildWorkflowRunSummaries(taskStatuses, limit: 8);
  final jobs = buildJobSummaries(taskStatuses, limit: 8);
  final slaBreaches = queueLatency.fold<int>(
    0,
    (total, row) => total + row.slaBreaches,
  );
  final throughputHint = throughput == null
      ? 'Waiting for another snapshot to estimate rate.'
      : 'Net change over the last ${throughput.interval.inSeconds}s.';

  final metrics =
      '''
<section id="overview-metrics" class="cards">
  ${buildMetricCard('Backlog (lag)', formatInt(totalPending), 'Undelivered tasks waiting across all queues.')}
  ${buildMetricCard('Processing', formatInt(totalInflight), 'Active envelopes currently being executed.')}
  ${buildMetricCard('Processed / min', formatRate(processedPerMin), throughputHint)}
  ${buildMetricCard('Enqueued / min', formatRate(enqueuedPerMin), throughputHint)}
  ${buildMetricCard('Dead letters', formatInt(totalDead), 'Items held in dead letter queues.')}
  ${buildMetricCard('Active workers', formatInt(activeWorkers), 'Workers that published heartbeats within the retention window.')}
  ${buildMetricCard('Running tasks', formatInt(runningTasks.length), 'Latest persisted statuses currently in running state.')}
  ${buildMetricCard('Failed tasks', formatInt(failedTasks.length), 'Latest persisted statuses that ended in failure.')}
  ${buildMetricCard('Workflow tasks', formatInt(workflowTasks.length), 'Recent task statuses tied to workflow execution.')}
  ${buildMetricCard('Stuck queued', formatInt(stuckQueued), 'Queued longer than ${queuedStuckThreshold.inMinutes}m.')}
  ${buildMetricCard('Stuck running', formatInt(stuckRunning), 'Running longer than ${runningStuckThreshold.inMinutes}m.')}
  ${buildMetricCard('SLA breaches', formatInt(slaBreaches), 'Queue wait > 1m or processing > 5m in recent statuses.')}
</section>
''';

  final namespaceSection =
      '''
<section id="overview-namespaces" class="table-card mt-7 ring-1 ring-inset ring-sky-300/10">
  <header class="border-b border-slate-300/10 px-4 py-3">
    <h2 class="text-sm font-semibold uppercase tracking-wider text-slate-300">Namespaces</h2>
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
      </tr>
    </thead>
    <tbody>
      ${namespaces.isEmpty ? '''
<tr>
  <td colspan="9" class="muted">No namespaces discovered yet.</td>
</tr>
''' : namespaces.map((summary) => '''
<tr>
  <td><span class="pill">${escapeHtml(summary.namespace)}</span></td>
  <td>${formatInt(summary.queueCount)}</td>
  <td>${formatInt(summary.workerCount)}</td>
  <td>${formatInt(summary.pending)}</td>
  <td>${formatInt(summary.inflight)}</td>
  <td>${formatInt(summary.deadLetters)}</td>
  <td>${formatInt(summary.runningTasks)}</td>
  <td>${formatInt(summary.failedTasks)}</td>
  <td>${formatInt(summary.workflowRuns)}</td>
</tr>
''').join()}
    </tbody>
  </table>
</section>
''';

  final topQueuesSection =
      '''
<section id="overview-queue-table" class="table-card ring-1 ring-inset ring-sky-300/10">
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
      ${topQueues.isEmpty ? buildEmptyQueuesRow('No queues detected yet.') : topQueues.map(buildQueueTableRow).join()}
    </tbody>
  </table>
</section>
''';

  final workflowSection =
      '''
<section id="overview-workflows" class="table-card mt-7 ring-1 ring-inset ring-sky-300/10">
  <header class="border-b border-slate-300/10 px-4 py-3">
    <h2 class="text-sm font-semibold uppercase tracking-wider text-slate-300">Workflow Runs (Sample)</h2>
  </header>
  <table>
    <thead>
      <tr>
        <th scope="col">Run ID</th>
        <th scope="col">Workflow</th>
        <th scope="col">Step</th>
        <th scope="col">Queued</th>
        <th scope="col">Running</th>
        <th scope="col">Succeeded</th>
        <th scope="col">Failed</th>
        <th scope="col">Cancelled</th>
        <th scope="col">Updated</th>
      </tr>
    </thead>
    <tbody>
      ${workflowRuns.isEmpty ? '''
<tr>
  <td colspan="9" class="muted">No workflow run metadata found in sampled task statuses.</td>
</tr>
''' : workflowRuns.map((run) => '''
<tr>
  <td><a class="font-semibold text-sky-200 hover:text-sky-100" href="/tasks/detail?runId=${Uri.encodeQueryComponent(run.runId)}" data-turbo-frame="dashboard-content"><code>${escapeHtml(run.runId)}</code></a></td>
  <td>${escapeHtml(run.workflowName)}</td>
  <td class="muted">${escapeHtml(run.lastStep ?? '—')}</td>
  <td>${formatInt(run.queued)}</td>
  <td>${formatInt(run.running)}</td>
  <td>${formatInt(run.succeeded)}</td>
  <td>${formatInt(run.failed)}</td>
  <td>${formatInt(run.cancelled)}</td>
  <td class="muted">${formatRelative(run.lastUpdated)}</td>
</tr>
''').join()}
    </tbody>
  </table>
</section>
''';

  final jobSection =
      '''
<section id="overview-jobs" class="table-card mt-7 ring-1 ring-inset ring-sky-300/10">
  <header class="border-b border-slate-300/10 px-4 py-3">
    <h2 class="text-sm font-semibold uppercase tracking-wider text-slate-300">Jobs (Task Families)</h2>
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
        <th scope="col">Failure ratio</th>
        <th scope="col">Updated</th>
      </tr>
    </thead>
    <tbody>
      ${jobs.isEmpty ? '''
<tr>
  <td colspan="9" class="muted">No task families discovered yet.</td>
</tr>
''' : jobs.map((job) => '''
<tr>
  <td>${escapeHtml(job.taskName)}</td>
  <td><span class="pill">${escapeHtml(job.sampleQueue)}</span></td>
  <td>${formatInt(job.total)}</td>
  <td>${formatInt(job.running)}</td>
  <td>${formatInt(job.succeeded)}</td>
  <td>${formatInt(job.failed)}</td>
  <td>${formatInt(job.retried)}</td>
  <td>${(job.failureRatio * 100).toStringAsFixed(1)}%</td>
  <td class="muted">${formatRelative(job.lastUpdated)}</td>
</tr>
''').join()}
    </tbody>
  </table>
</section>
''';

  final latencySection =
      '''
<section id="overview-latency-table" class="table-card mt-7 ring-1 ring-inset ring-sky-300/10">
  <table>
    <thead>
      <tr>
        <th scope="col">Queue</th>
        <th scope="col">Samples</th>
        <th scope="col">Wait avg</th>
        <th scope="col">Run avg</th>
        <th scope="col">SLA breaches</th>
      </tr>
    </thead>
    <tbody>
      ${queueLatency.isEmpty ? '''
<tr>
  <td colspan="5" class="muted">No queue latency samples available yet.</td>
</tr>
''' : queueLatency.map((row) => '''
<tr>
  <td><span class="pill">${escapeHtml(row.queue)}</span></td>
  <td>${formatInt(row.samples)}</td>
  <td>${row.avgWaitLabel}</td>
  <td>${row.avgRunLabel}</td>
  <td>${formatInt(row.slaBreaches)}</td>
</tr>
''').join()}
    </tbody>
  </table>
</section>
''';

  final recentTasksSection =
      '''
<section id="overview-recent-tasks" class="table-card mt-7 ring-1 ring-inset ring-sky-300/10">
  ${buildTaskStatusTable(
    taskStatuses.take(8).toList(growable: false),
    options: const DashboardTaskTableOptions(
      showAttempt: false,
      showError: false,
      showActions: false,
      emptyMessage: 'No persisted task statuses yet.',
    ),
  )}
</section>
''';

  return OverviewSections(
    metrics: metrics,
    namespaces: namespaceSection,
    topQueues: topQueuesSection,
    workflows: workflowSection,
    jobs: jobSection,
    latency: latencySection,
    recentTasks: recentTasksSection,
  );
}

List<_QueueLatencyRow> _buildQueueLatency(
  List<DashboardTaskStatusEntry> tasks,
) {
  final byQueue = <String, _QueueLatencyAccumulator>{};
  const queueSla = Duration(minutes: 1);
  const runSla = Duration(minutes: 5);

  for (final task in tasks) {
    byQueue
        .putIfAbsent(
          task.queue,
          () => _QueueLatencyAccumulator(queue: task.queue),
        )
        .add(
          wait: task.queueWait,
          run: task.processingTime,
          queueSla: queueSla,
          runSla: runSla,
        );
  }

  final rows =
      byQueue.values.map((value) => value.build()).toList(growable: false)
        ..sort((a, b) => b.slaBreaches.compareTo(a.slaBreaches));
  return rows.take(8).toList(growable: false);
}

class _QueueLatencyAccumulator {
  _QueueLatencyAccumulator({required this.queue});

  final String queue;
  final _wait = <int>[];
  final _run = <int>[];
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
      _wait.add(wait.inMilliseconds);
      if (wait > queueSla) _breaches += 1;
    }
    if (run != null) {
      _run.add(run.inMilliseconds);
      if (run > runSla) _breaches += 1;
    }
  }

  _QueueLatencyRow build() {
    return _QueueLatencyRow(
      queue: queue,
      samples: _samples,
      avgWaitMs: _average(_wait),
      avgRunMs: _average(_run),
      slaBreaches: _breaches,
    );
  }

  int _average(List<int> values) {
    if (values.isEmpty) return 0;
    final total = values.fold<int>(0, (sum, value) => sum + value);
    return (total / values.length).round();
  }
}

class _QueueLatencyRow {
  const _QueueLatencyRow({
    required this.queue,
    required this.samples,
    required this.avgWaitMs,
    required this.avgRunMs,
    required this.slaBreaches,
  });

  final String queue;
  final int samples;
  final int avgWaitMs;
  final int avgRunMs;
  final int slaBreaches;

  String get avgWaitLabel => _formatMs(avgWaitMs);
  String get avgRunLabel => _formatMs(avgRunMs);

  String _formatMs(int millis) {
    if (millis <= 0) return '—';
    if (millis < 1000) return '${millis}ms';
    return '${(millis / 1000).toStringAsFixed(2)}s';
  }
}
