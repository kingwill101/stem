// Public helper functions in this file are intentionally undocumented to keep
// UI template files lightweight.
// ignore_for_file: public_member_api_docs

import 'package:stem_dashboard/src/services/models.dart';
import 'package:stem_dashboard/src/ui/shared.dart';

String buildOverviewContent(
  List<QueueSummary> queues,
  List<WorkerStatus> workers,
  DashboardThroughput? throughput,
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
  final throughputHint = throughput == null
      ? 'Waiting for another snapshot to estimate rate.'
      : 'Net change over the last ${throughput.interval.inSeconds}s.';

  return '''
<section class="page-header">
  <h1>Overview</h1>
  <p class="page-subtitle">
    Live snapshot of Stem throughput and worker health. Metrics refresh with every navigation and Turbo frame update.
  </p>
</section>

<section class="cards">
  ${buildMetricCard('Backlog (lag)', formatInt(totalPending), 'Undelivered tasks waiting across all queues.')}
  ${buildMetricCard('Processing', formatInt(totalInflight), 'Active envelopes currently being executed.')}
  ${buildMetricCard('Processed / min', formatRate(processedPerMin), throughputHint)}
  ${buildMetricCard('Enqueued / min', formatRate(enqueuedPerMin), throughputHint)}
  ${buildMetricCard('Dead letters', formatInt(totalDead), 'Items held in dead letter queues.')}
  ${buildMetricCard('Active workers', formatInt(activeWorkers), 'Workers that published heartbeats within the retention window.')}
</section>

<section class="table-card">
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
}
