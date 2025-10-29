import 'package:intl/intl.dart';

import '../services/models.dart';

final _eventTimeFormat = DateFormat('HH:mm:ss');

String renderEventItem(DashboardEvent event) {
  final timestamp = _eventTimeFormat.format(event.timestamp.toLocal());
  final metadataItems = event.metadata.entries
      .map((entry) => '<span>${entry.key}: ${entry.value}</span>')
      .join();
  final summary = event.summary != null && event.summary!.isNotEmpty
      ? '<p class="muted">${event.summary}</p>'
      : '';

  return '''
<details class="event-item" data-event>
  <summary>
    <span class="event-title">${event.title}</span>
    <span class="event-time">$timestamp</span>
  </summary>
  $summary
  ${metadataItems.isEmpty ? '' : '<div class="event-meta">$metadataItems</div>'}
</details>
''';
}
