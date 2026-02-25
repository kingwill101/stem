import 'package:intl/intl.dart';

import 'package:stem_dashboard/src/services/models.dart';

final _eventTimeFormat = DateFormat('HH:mm:ss');

/// Renders a dashboard event as an HTML list item.
String renderEventItem(DashboardEvent event) {
  final timestamp = _eventTimeFormat.format(event.timestamp.toLocal());
  final metadataItems = event.metadata.entries
      .map((entry) => '<span>${entry.key}: ${entry.value}</span>')
      .join();
  final summary = event.summary != null && event.summary!.isNotEmpty
      ? '<p class="muted mt-3 leading-relaxed">${event.summary}</p>'
      : '';

  return '''
<details class="event-item ring-1 ring-inset ring-sky-300/10" data-event>
  <summary>
    <span class="event-title">${event.title}</span>
    <span class="event-time">$timestamp</span>
  </summary>
  $summary
  ${metadataItems.isEmpty ? '' : '<div class="event-meta">$metadataItems</div>'}
</details>
''';
}
