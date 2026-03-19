import 'package:stem_dashboard/src/services/models.dart';
import 'package:stem_dashboard/src/ui/audit.dart';
import 'package:stem_dashboard/src/ui/events.dart';
import 'package:stem_dashboard/src/ui/failures.dart';
import 'package:stem_dashboard/src/ui/jobs.dart';
import 'package:stem_dashboard/src/ui/layout.dart';
import 'package:stem_dashboard/src/ui/namespaces.dart';
import 'package:stem_dashboard/src/ui/options.dart';
import 'package:stem_dashboard/src/ui/overview.dart';
import 'package:stem_dashboard/src/ui/search.dart';
import 'package:stem_dashboard/src/ui/task_detail.dart';
import 'package:stem_dashboard/src/ui/tasks.dart';
import 'package:stem_dashboard/src/ui/workers.dart';
import 'package:stem_dashboard/src/ui/workflows.dart';

export 'package:stem_dashboard/src/ui/options.dart';

/// Builds the HTML for the specified dashboard [page].
String buildPageContent({
  required DashboardPage page,
  required List<QueueSummary> queues,
  required List<WorkerStatus> workers,
  List<DashboardTaskStatusEntry> taskStatuses = const [],
  DashboardTaskStatusEntry? taskDetail,
  List<DashboardTaskStatusEntry> runTimeline = const [],
  DashboardWorkflowRunSnapshot? workflowRun,
  List<DashboardWorkflowCheckpointSnapshot> workflowCheckpoints = const [],
  List<DashboardAuditEntry> auditEntries = const [],
  DashboardThroughput? throughput,
  List<DashboardEvent> events = const [],
  String defaultNamespace = 'stem',
  TasksPageOptions tasksOptions = const TasksPageOptions(),
  WorkersPageOptions workersOptions = const WorkersPageOptions(),
  FailuresPageOptions failuresOptions = const FailuresPageOptions(),
  SearchPageOptions searchOptions = const SearchPageOptions(),
  NamespacesPageOptions namespacesOptions = const NamespacesPageOptions(),
  WorkflowsPageOptions workflowsOptions = const WorkflowsPageOptions(),
  JobsPageOptions jobsOptions = const JobsPageOptions(),
}) {
  switch (page) {
    case DashboardPage.overview:
      return buildOverviewContent(
        queues,
        workers,
        throughput,
        taskStatuses,
        defaultNamespace,
      );
    case DashboardPage.tasks:
      return buildTasksContent(queues, tasksOptions, taskStatuses);
    case DashboardPage.taskDetail:
      return buildTaskDetailContent(
        taskDetail,
        runTimeline,
        workflowRun,
        workflowCheckpoints,
      );
    case DashboardPage.failures:
      return buildFailuresContent(taskStatuses, failuresOptions);
    case DashboardPage.search:
      return buildSearchContent(
        options: searchOptions,
        queues: queues,
        workers: workers,
        taskStatuses: taskStatuses,
        auditEntries: auditEntries,
      );
    case DashboardPage.audit:
      return buildAuditContent(auditEntries);
    case DashboardPage.events:
      return buildEventsContent(events);
    case DashboardPage.workers:
      return buildWorkersContent(workers, queues, workersOptions);
    case DashboardPage.namespaces:
      return buildNamespacesContent(
        queues: queues,
        workers: workers,
        taskStatuses: taskStatuses,
        options: namespacesOptions,
        defaultNamespace: defaultNamespace,
      );
    case DashboardPage.workflows:
      return buildWorkflowsContent(
        taskStatuses: taskStatuses,
        options: workflowsOptions,
      );
    case DashboardPage.jobs:
      return buildJobsContent(taskStatuses: taskStatuses, options: jobsOptions);
  }
}

/// Builds inline expandable-row content for task table details.
String buildTaskInlineContent(DashboardTaskStatusEntry? task) {
  return buildTaskInlinePanel(task);
}
