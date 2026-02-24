import 'package:stem_dashboard/src/services/models.dart';
import 'package:stem_dashboard/src/ui/events.dart';
import 'package:stem_dashboard/src/ui/layout.dart';
import 'package:stem_dashboard/src/ui/options.dart';
import 'package:stem_dashboard/src/ui/overview.dart';
import 'package:stem_dashboard/src/ui/tasks.dart';
import 'package:stem_dashboard/src/ui/workers.dart';

export 'package:stem_dashboard/src/ui/options.dart';

/// Builds the HTML for the specified dashboard [page].
String buildPageContent({
  required DashboardPage page,
  required List<QueueSummary> queues,
  required List<WorkerStatus> workers,
  DashboardThroughput? throughput,
  List<DashboardEvent> events = const [],
  TasksPageOptions tasksOptions = const TasksPageOptions(),
  WorkersPageOptions workersOptions = const WorkersPageOptions(),
}) {
  switch (page) {
    case DashboardPage.overview:
      return buildOverviewContent(queues, workers, throughput);
    case DashboardPage.tasks:
      return buildTasksContent(queues, tasksOptions);
    case DashboardPage.events:
      return buildEventsContent(events);
    case DashboardPage.workers:
      return buildWorkersContent(workers, queues, workersOptions);
  }
}
