import 'package:intl/intl.dart';
import 'package:stem/stem.dart' show stemNow;
// Public helper functions in this file are intentionally undocumented to keep
// UI template files lightweight.
// ignore_for_file: public_member_api_docs

import 'package:stem_dashboard/src/services/models.dart';

final dashboardNumberFormat = NumberFormat.decimalPattern();

String buildQueueTableRow(QueueSummary summary) {
  return '''
<tr class="queue-row" data-queue-row="${summary.queue}">
  <td><span class="pill">${summary.queue}</span></td>
  <td>${formatInt(summary.pending)}</td>
  <td>${formatInt(summary.inflight)}</td>
  <td>${formatInt(summary.deadLetters)}</td>
</tr>
<tr class="queue-detail" data-queue-detail="${summary.queue}">
  <td colspan="4">
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
<article class="card">
  <div class="card-title">$title</div>
  <div class="card-value">$value</div>
  <p class="card-caption">$caption</p>
</article>
''';
}

String buildEmptyQueuesRow(String message) {
  return '''
<tr>
  <td colspan="4" class="muted">$message</td>
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
