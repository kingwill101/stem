// Public helper functions in this file are intentionally undocumented to keep
// UI template files lightweight.
// ignore_for_file: public_member_api_docs

import 'package:stem_dashboard/src/services/models.dart';
import 'package:stem_dashboard/src/ui/shared.dart';

String buildAuditContent(List<DashboardAuditEntry> entries) {
  final actions = entries.where((entry) => entry.kind == 'action').length;
  final alerts = entries.where((entry) => entry.kind == 'alert').length;
  final failures = entries.where((entry) => entry.status == 'error').length;

  return '''
<section class="page-header rounded-2xl border border-slate-300/15 bg-slate-900/45 px-5 py-5">
  <h1>Audit Log</h1>
  <p class="page-subtitle">
    Operator actions and automated alert deliveries are captured here for post-incident review.
  </p>
</section>

<section class="cards">
  ${buildMetricCard('Entries', formatInt(entries.length), 'Recent audit records retained in dashboard memory.')}
  ${buildMetricCard('Actions', formatInt(actions), 'Control/replay/revoke operations initiated by operators.')}
  ${buildMetricCard('Alerts', formatInt(alerts), 'Automated threshold alerts emitted by polling logic.')}
  ${buildMetricCard('Errors', formatInt(failures), 'Entries with status=error requiring follow-up.')}
</section>

<section class="table-card ring-1 ring-inset ring-sky-300/10">
  <header class="border-b border-slate-300/10 px-4 py-3">
    <h2 class="text-sm font-semibold uppercase tracking-wider text-slate-300">Timeline</h2>
  </header>
  <table>
    <thead>
      <tr>
        <th scope="col">Time</th>
        <th scope="col">Kind</th>
        <th scope="col">Action</th>
        <th scope="col">Status</th>
        <th scope="col">Actor</th>
        <th scope="col">Summary</th>
        <th scope="col">Metadata</th>
      </tr>
    </thead>
    <tbody>
      ${entries.isEmpty ? '''
<tr>
  <td colspan="7" class="muted">No audit entries yet.</td>
</tr>
''' : entries.take(250).map((entry) => '''
<tr>
  <td class="muted">${formatRelative(entry.timestamp)}</td>
  <td>${escapeHtml(entry.kind)}</td>
  <td>${escapeHtml(entry.action)}</td>
  <td><span class="pill ${entry.status == 'ok' || entry.status == 'sent'
            ? 'success'
            : entry.status == 'error'
            ? 'error'
            : 'warning'}">${escapeHtml(entry.status)}</span></td>
  <td class="muted">${escapeHtml(entry.actor ?? 'system')}</td>
  <td class="muted">${escapeHtml(entry.summary ?? '—')}</td>
  <td class="muted">${escapeHtml(_formatMetadata(entry.metadata))}</td>
</tr>
''').join()}
    </tbody>
  </table>
</section>
''';
}

String _formatMetadata(Map<String, Object?> metadata) {
  if (metadata.isEmpty) return '—';
  final values = metadata.entries
      .map((entry) => '${entry.key}=${entry.value}')
      .toList(growable: false);
  return values.join(', ');
}
