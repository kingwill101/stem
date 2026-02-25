// Public helper functions in this file are intentionally undocumented to keep
// UI template files lightweight.
// ignore_for_file: public_member_api_docs

import 'package:stem_dashboard/src/services/models.dart';
import 'package:stem_dashboard/src/ui/event_templates.dart';

String buildEventsContent(List<DashboardEvent> events) {
  final items = events.isEmpty
      ? '''
        <div class="event-item ring-1 ring-inset ring-sky-300/10" id="event-log-placeholder">
          <h3 class="text-lg font-semibold text-slate-100">No events captured yet</h3>
          <p class="muted">
            Configure the dashboard event bridge to stream Stem signals (enqueue, start, retry, completion) into Redis.
            Once connected, updates will appear here automatically via Turbo Streams.
          </p>
        </div>
      '''
      : events.map(renderEventItem).join();

  return '''
<section class="page-header rounded-2xl border border-slate-300/15 bg-slate-900/45 px-5 py-5">
  <h1>Events</h1>
  <p class="page-subtitle">
    Task lifecycle, retry, and worker log events stream into this feed. Turbo handles incremental updates without full-page reloads.
  </p>
</section>

<section class="event-feed rounded-2xl border border-slate-300/10 bg-slate-900/20 p-3 sm:p-4" id="event-log">
  $items
</section>
''';
}
