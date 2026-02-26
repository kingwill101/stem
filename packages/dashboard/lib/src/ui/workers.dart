// Public helper functions in this file are intentionally undocumented to keep
// UI template files lightweight.
// ignore_for_file: public_member_api_docs

import 'dart:math' as math;

import 'package:stem_dashboard/src/services/models.dart';
import 'package:stem_dashboard/src/ui/options.dart';
import 'package:stem_dashboard/src/ui/shared.dart';

String buildWorkersContent(
  List<WorkerStatus> workers,
  List<QueueSummary> queues,
  WorkersPageOptions options,
) {
  final filteredWorkers = options.hasNamespaceFilter
      ? workers
            .where(
              (worker) =>
                  worker.namespace.toLowerCase() ==
                  options.namespaceFilter!.toLowerCase(),
            )
            .toList(growable: false)
      : workers;
  final healthyWorkers = filteredWorkers.where((worker) {
    return worker.age <= const Duration(minutes: 2);
  }).length;

  final busy = filteredWorkers.where((worker) => worker.inflight > 0).length;
  final overloaded = filteredWorkers.where((worker) {
    final cap = worker.isolateCount <= 0 ? 1 : worker.isolateCount;
    return worker.inflight / cap >= 0.8;
  }).length;
  final queueCoverage = _buildQueueCoverage(filteredWorkers, queues);
  final imbalance = _computeImbalance(queueCoverage);
  final queueMap = {for (final summary in queues) summary.queue: summary};

  return '''
<section class="page-header rounded-2xl border border-slate-300/15 bg-slate-900/45 px-5 py-5">
  <h1>Workers</h1>
  <p class="page-subtitle">
    Heartbeat health, queue assignments, and in-flight counts. Issue control plane commands and replay dead letters inline.
  </p>
</section>

${renderWorkersAlert(options)}

<section class="cards">
  ${buildMetricCard('Healthy workers', formatInt(healthyWorkers), 'Heartbeats received within the last two minutes.')}
  ${buildMetricCard('Busy workers', formatInt(busy), 'Workers currently processing at least one task.')}
  ${buildMetricCard('High saturation', formatInt(overloaded), 'Workers at or above 80% inflight-to-isolate capacity.')}
  ${buildMetricCard('Queue imbalance', imbalance.toStringAsFixed(2), 'Stddev of worker coverage across discovered queues.')}
  ${buildMetricCard('Isolates in use', formatInt(totalIsolates(filteredWorkers)), 'Sum of worker isolates across the cluster.')}
</section>

<form class="filter-form rounded-2xl border border-slate-300/15 bg-slate-900/40 p-4" action="/workers" method="get" data-turbo-frame="dashboard-content">
  <label class="filter-label" for="worker-namespace-filter">Namespace</label>
  <input id="worker-namespace-filter" name="namespace" value="${escapeHtml(options.namespaceFilter ?? '')}" placeholder="stem" />
  <button type="submit">Apply</button>
  ${options.hasNamespaceFilter ? '<a class="clear-filter" href="/workers" data-turbo-frame="dashboard-content">Clear</a>' : ''}
</form>

<section class="table-card ring-1 ring-inset ring-sky-300/10">
  <header class="border-b border-slate-300/10 px-4 py-3">
    <h2 class="text-sm font-semibold uppercase tracking-wider text-slate-300">Worker Heartbeats</h2>
  </header>
  <table>
    <thead>
      <tr>
        <th scope="col">Worker</th>
        <th scope="col">Namespace</th>
        <th scope="col">Queues</th>
        <th scope="col">Inflight</th>
        <th scope="col">Saturation</th>
        <th scope="col">Last heartbeat</th>
        <th scope="col">Actions</th>
      </tr>
    </thead>
    <tbody>
      ${filteredWorkers.isEmpty ? '''
              <tr>
                <td colspan="7" class="muted">No heartbeats detected for namespace "${escapeHtml(options.namespaceFilter ?? 'stem')}".</td>
              </tr>
            ''' : filteredWorkers.map((worker) => buildWorkerRow(worker, namespaceFilter: options.namespaceFilter)).join()}
    </tbody>
  </table>
</section>

${_buildQueueCoverageSection(queueCoverage)}

${buildClusterControls(namespaceFilter: options.namespaceFilter)}

${buildQueueRecoverySection(queueMap, namespaceFilter: options.namespaceFilter)}
''';
}

String buildWorkerRow(WorkerStatus status, {String? namespaceFilter}) {
  final queues = status.queues.isEmpty
      ? '<span class="muted">—</span>'
      : status.queues
            .map(
              (queue) => '<span class="pill">${escapeHtml(queue.name)}</span>',
            )
            .join(' ');
  return '''
<tr>
  <td class="font-semibold text-slate-100">${escapeHtml(status.workerId)}</td>
  <td><span class="pill">${escapeHtml(status.namespace)}</span></td>
  <td>$queues</td>
  <td>${formatInt(status.inflight)}</td>
  <td>${buildSaturationPill(status)}</td>
  <td class="muted">${formatRelative(status.timestamp)}</td>
  <td>
    <div class="action-bar">
      ${buildWorkerActionButton('Ping', 'ping', status.workerId, namespaceFilter: namespaceFilter)}
      ${buildWorkerActionButton('Pause', 'pause', status.workerId, namespaceFilter: namespaceFilter)}
      ${buildWorkerActionButton('Shutdown', 'shutdown', status.workerId, namespaceFilter: namespaceFilter)}
    </div>
  </td>
</tr>
''';
}

String buildSaturationPill(WorkerStatus status) {
  final capacity = status.isolateCount <= 0 ? 1 : status.isolateCount;
  final ratio = status.inflight / capacity;
  final label = '${(ratio * 100).round()}%';
  final style = ratio >= 0.8
      ? 'error'
      : ratio >= 0.5
      ? 'warning'
      : 'success';
  return '<span class="pill $style">$label</span>';
}

String buildWorkerActionButton(
  String label,
  String action,
  String workerId, {
  String? namespaceFilter,
}) {
  return '''
<form class="inline-form" action="/workers/control" method="post" data-turbo-frame="dashboard-content">
  <input type="hidden" name="worker" value="${escapeHtml(workerId)}" />
  <input type="hidden" name="action" value="${escapeHtml(action)}" />
  ${namespaceFilter == null || namespaceFilter.isEmpty ? '' : '<input type="hidden" name="namespace" value="${escapeHtml(namespaceFilter)}" />'}
  <button type="submit" class="ghost-button">$label</button>
</form>
''';
}

String buildClusterControls({String? namespaceFilter}) {
  return '''
<section class="control-panel ring-1 ring-inset ring-sky-300/10">
  <h2 class="section-heading">Cluster controls</h2>
  <p class="muted mb-3">Broadcast commands to all workers in the namespace.</p>
  <div class="action-bar">
    ${buildClusterActionButton('Ping all workers', 'ping', namespaceFilter: namespaceFilter)}
    ${buildClusterActionButton('Pause all workers', 'pause', namespaceFilter: namespaceFilter)}
    ${buildClusterActionButton('Shutdown all workers', 'shutdown', namespaceFilter: namespaceFilter)}
  </div>
</section>
''';
}

String buildClusterActionButton(
  String label,
  String action, {
  String? namespaceFilter,
}) {
  return '''
<form class="inline-form" action="/workers/control" method="post" data-turbo-frame="dashboard-content">
  <input type="hidden" name="worker" value="*" />
  <input type="hidden" name="action" value="${escapeHtml(action)}" />
  ${namespaceFilter == null || namespaceFilter.isEmpty ? '' : '<input type="hidden" name="namespace" value="${escapeHtml(namespaceFilter)}" />'}
  <button type="submit" class="ghost-button">$label</button>
</form>
''';
}

String buildQueueRecoverySection(
  Map<String, QueueSummary> queues, {
  String? namespaceFilter,
}) {
  if (queues.isEmpty) return '';
  final rows = queues.values.toList()
    ..sort((a, b) => a.queue.compareTo(b.queue));
  return '''
<section class="table-card mt-7 ring-1 ring-inset ring-sky-300/10">
  <header class="border-b border-slate-300/10 px-4 py-3">
    <h2 class="text-sm font-semibold uppercase tracking-wider text-slate-300">Queue Recovery</h2>
  </header>
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
      ${rows.map((summary) => buildQueueRecoveryRow(summary, namespaceFilter: namespaceFilter)).join()}
    </tbody>
  </table>
</section>
''';
}

String _buildQueueCoverageSection(List<_QueueCoverageRow> rows) {
  if (rows.isEmpty) return '';
  return '''
<section class="table-card mt-7 ring-1 ring-inset ring-sky-300/10">
  <header class="border-b border-slate-300/10 px-4 py-3">
    <h2 class="text-sm font-semibold uppercase tracking-wider text-slate-300">Queue Coverage</h2>
  </header>
  <table>
    <thead>
      <tr>
        <th scope="col">Queue</th>
        <th scope="col">Workers assigned</th>
        <th scope="col">Inflight load</th>
        <th scope="col">Pending</th>
        <th scope="col">Dead letters</th>
      </tr>
    </thead>
    <tbody>
      ${rows.map((row) => '''
<tr>
  <td><span class="pill">${escapeHtml(row.queue)}</span></td>
  <td>${formatInt(row.workerCount)}</td>
  <td>${formatInt(row.inflight)}</td>
  <td>${formatInt(row.pending)}</td>
  <td>${formatInt(row.deadLetters)}</td>
</tr>
''').join()}
    </tbody>
  </table>
</section>
''';
}

List<_QueueCoverageRow> _buildQueueCoverage(
  List<WorkerStatus> workers,
  List<QueueSummary> queues,
) {
  final map = <String, _QueueCoverageRowBuilder>{};
  for (final queue in queues) {
    map.putIfAbsent(
      queue.queue,
      () => _QueueCoverageRowBuilder(
        queue: queue.queue,
        pending: queue.pending,
        deadLetters: queue.deadLetters,
      ),
    );
  }
  for (final worker in workers) {
    for (final queue in worker.queues) {
      final entry = map.putIfAbsent(
        queue.name,
        () => _QueueCoverageRowBuilder(queue: queue.name),
      );
      entry.workers.add(worker.workerId);
      entry.inflight += queue.inflight;
    }
  }
  final rows = map.values.map((value) => value.build()).toList(growable: false)
    ..sort((a, b) {
      final byWorkers = a.workerCount.compareTo(b.workerCount);
      if (byWorkers != 0) return byWorkers;
      return b.pending.compareTo(a.pending);
    });
  return rows;
}

double _computeImbalance(List<_QueueCoverageRow> rows) {
  if (rows.length <= 1) return 0;
  final values = rows.map((row) => row.workerCount.toDouble()).toList();
  final mean = values.reduce((a, b) => a + b) / values.length;
  var variance = 0.0;
  for (final value in values) {
    final delta = value - mean;
    variance += delta * delta;
  }
  variance /= values.length;
  return math.sqrt(variance);
}

class _QueueCoverageRowBuilder {
  _QueueCoverageRowBuilder({
    required this.queue,
    this.pending = 0,
    this.deadLetters = 0,
  });

  final String queue;
  final Set<String> workers = <String>{};
  int inflight = 0;
  int pending;
  int deadLetters;

  _QueueCoverageRow build() {
    return _QueueCoverageRow(
      queue: queue,
      workerCount: workers.length,
      inflight: inflight,
      pending: pending,
      deadLetters: deadLetters,
    );
  }
}

class _QueueCoverageRow {
  const _QueueCoverageRow({
    required this.queue,
    required this.workerCount,
    required this.inflight,
    required this.pending,
    required this.deadLetters,
  });

  final String queue;
  final int workerCount;
  final int inflight;
  final int pending;
  final int deadLetters;
}

String buildQueueRecoveryRow(QueueSummary summary, {String? namespaceFilter}) {
  final limitDefault = summary.deadLetters <= 0
      ? 50
      : summary.deadLetters.clamp(1, 50);
  final redirect = namespaceFilter == null || namespaceFilter.isEmpty
      ? '/workers'
      : '/workers?namespace=${Uri.encodeQueryComponent(namespaceFilter)}';
  final action = summary.deadLetters == 0
      ? '<span class="muted">No dead letters</span>'
      : '''
      <form class="inline-form" action="/queues/replay" method="post" data-turbo-frame="dashboard-content">
        <input type="hidden" name="queue" value="${escapeHtml(summary.queue)}" />
        <input type="hidden" name="limit" value="$limitDefault" />
        <input type="hidden" name="redirect" value="$redirect" />
        <button type="submit" class="ghost-button">Replay</button>
      </form>
    ''';
  return '''
<tr>
  <td><span class="pill">${escapeHtml(summary.queue)}</span></td>
  <td>${formatInt(summary.pending)}</td>
  <td>${formatInt(summary.deadLetters)}</td>
  <td>$action</td>
</tr>
''';
}

String renderWorkersAlert(WorkersPageOptions options) {
  if (options.hasError) {
    final scope = options.hasScope
        ? '<div class="muted">Target: ${escapeHtml(options.scope!)}.</div>'
        : '';
    return '''
<div class="flash error">
  ${escapeHtml(options.errorMessage!)}
  $scope
</div>
''';
  }
  if (options.hasFlash) {
    final scope = options.hasScope
        ? '<div class="muted">Target: ${escapeHtml(options.scope!)}.</div>'
        : '';
    return '''
<div class="flash success">
  ${escapeHtml(options.flashMessage!)}
  $scope
</div>
''';
  }
  return '';
}
