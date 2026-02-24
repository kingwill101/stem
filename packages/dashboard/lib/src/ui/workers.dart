// Public helper functions in this file are intentionally undocumented to keep
// UI template files lightweight.
// ignore_for_file: public_member_api_docs

import 'package:stem_dashboard/src/services/models.dart';
import 'package:stem_dashboard/src/ui/options.dart';
import 'package:stem_dashboard/src/ui/shared.dart';

String buildWorkersContent(
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

${renderWorkersAlert(options)}

<section class="cards">
  ${buildMetricCard('Healthy workers', formatInt(healthyWorkers), 'Heartbeats received within the last two minutes.')}
  ${buildMetricCard('Busy workers', formatInt(busy), 'Workers currently processing at least one task.')}
  ${buildMetricCard('Isolates in use', formatInt(totalIsolates(workers)), 'Sum of worker isolates across the cluster.')}
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
            ''' : workers.map(buildWorkerRow).join()}
    </tbody>
  </table>
</section>

${buildClusterControls()}

${buildQueueRecoverySection(queueMap)}
''';
}

String buildWorkerRow(WorkerStatus status) {
  final queues = status.queues.isEmpty
      ? '<span class="muted">—</span>'
      : status.queues
            .map((queue) => '<span class="pill">${queue.name}</span>')
            .join(' ');
  return '''
<tr>
  <td>${status.workerId}</td>
  <td>$queues</td>
  <td>${formatInt(status.inflight)}</td>
  <td class="muted">${formatRelative(status.timestamp)}</td>
  <td>
    <div class="action-bar">
      ${buildWorkerActionButton('Ping', 'ping', status.workerId)}
      ${buildWorkerActionButton('Pause', 'pause', status.workerId)}
      ${buildWorkerActionButton('Shutdown', 'shutdown', status.workerId)}
    </div>
  </td>
</tr>
''';
}

String buildWorkerActionButton(String label, String action, String workerId) {
  return '''
<form class="inline-form" action="/workers/control" method="post" data-turbo-frame="dashboard-content">
  <input type="hidden" name="worker" value="${escapeHtml(workerId)}" />
  <input type="hidden" name="action" value="${escapeHtml(action)}" />
  <button type="submit" class="ghost-button">$label</button>
</form>
''';
}

String buildClusterControls() {
  return '''
<section class="control-panel">
  <h2 class="section-heading">Cluster controls</h2>
  <div class="action-bar">
    ${buildClusterActionButton('Ping all workers', 'ping')}
    ${buildClusterActionButton('Pause all workers', 'pause')}
    ${buildClusterActionButton('Shutdown all workers', 'shutdown')}
  </div>
</section>
''';
}

String buildClusterActionButton(String label, String action) {
  return '''
<form class="inline-form" action="/workers/control" method="post" data-turbo-frame="dashboard-content">
  <input type="hidden" name="worker" value="*" />
  <input type="hidden" name="action" value="${escapeHtml(action)}" />
  <button type="submit" class="ghost-button">$label</button>
</form>
''';
}

String buildQueueRecoverySection(Map<String, QueueSummary> queues) {
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
      ${rows.map(buildQueueRecoveryRow).join()}
    </tbody>
  </table>
</section>
''';
}

String buildQueueRecoveryRow(QueueSummary summary) {
  final limitDefault = summary.deadLetters <= 0
      ? 50
      : summary.deadLetters.clamp(1, 50);
  final action = summary.deadLetters == 0
      ? '<span class="muted">No dead letters</span>'
      : '''
      <form class="inline-form" action="/queues/replay" method="post" data-turbo-frame="dashboard-content">
        <input type="hidden" name="queue" value="${escapeHtml(summary.queue)}" />
        <input type="hidden" name="limit" value="$limitDefault" />
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
