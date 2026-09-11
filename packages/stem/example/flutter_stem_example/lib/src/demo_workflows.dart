import 'dart:io';

import 'package:stem_flutter_sqlite/stem_flutter_sqlite.dart';
import 'package:stem_sqlite/stem_sqlite.dart';

import 'demo_config.dart';

enum WorkbenchWorkflowKind {
  report,
  sleep,
  approval;

  WorkbenchWorkflowDescriptor get descriptor =>
      demoWorkflowDescriptors.firstWhere((item) => item.kind == this);
}

class WorkbenchWorkflowDescriptor {
  const WorkbenchWorkflowDescriptor({
    required this.kind,
    required this.name,
    required this.title,
    required this.description,
  });

  final WorkbenchWorkflowKind kind;
  final String name;
  final String title;
  final String description;
}

const demoWorkflowDescriptors = [
  WorkbenchWorkflowDescriptor(
    kind: WorkbenchWorkflowKind.report,
    name: 'demo.report',
    title: 'Checkpointed report',
    description: 'Collect, total, and publish a small durable report.',
  ),
  WorkbenchWorkflowDescriptor(
    kind: WorkbenchWorkflowKind.sleep,
    name: 'demo.sleep',
    title: 'Durable sleep',
    description: 'Save a checkpoint, wait 10 seconds, then finish on a wakeup.',
  ),
  WorkbenchWorkflowDescriptor(
    kind: WorkbenchWorkflowKind.approval,
    name: 'demo.approval',
    title: 'Wait for approval',
    description: 'Persist a draft and wait for approval of this run only.',
  ),
];

String workflowApprovalTopic(String runId) => 'demo.approval.$runId';

/// Reconstructs code on every attachment; only data lives in SQLite.
///
/// Checkpoint handlers return non-null durable values. External effects still
/// need idempotency: a crash between an effect and checkpoint persistence can
/// replay the handler. This demo does not claim exactly-once external effects.
List<WorkflowScript> createDemoWorkflowScripts() => [
  WorkflowScript<Map<String, Object?>>(
    name: WorkbenchWorkflowKind.report.descriptor.name,
    checkpoints: [
      WorkflowCheckpoint(name: 'collect'),
      WorkflowCheckpoint(name: 'total'),
      WorkflowCheckpoint(name: 'publish'),
    ],
    run: (flow) async {
      final rows = await flow.step<List<Object?>>(
        'collect',
        (_) => [12, 8, 15],
      );
      final total = await flow.step(
        'total',
        (_) => rows.fold<int>(0, (sum, value) => sum + (value as int)),
      );
      return flow.step<Map<String, Object?>>(
        'publish',
        (_) => {'rows': rows.length, 'total': total},
      );
    },
  ),
  WorkflowScript<Map<String, Object?>>(
    name: WorkbenchWorkflowKind.sleep.descriptor.name,
    checkpoints: [
      WorkflowCheckpoint(name: 'prepare'),
      WorkflowCheckpoint(name: 'sleep'),
      WorkflowCheckpoint(name: 'finish'),
    ],
    run: (flow) async {
      final prepared = await flow.step<Map<String, Object?>>(
        'prepare',
        (_) => {'preparedAt': DateTime.now().toUtc().toIso8601String()},
      );
      await flow.step('sleep', (step) async {
        final delayMs = flow.params['delayMs'] ?? 10000;
        if (delayMs is! int || delayMs < 1 || delayMs > 60000) {
          throw ArgumentError('delayMs must be an integer from 1 to 60000');
        }
        // Sleep resumes with the persisted `payload` (true by default), not
        // the surrounding suspension metadata. Consume it before sleeping again.
        final resume = step.takeResumeData();
        if (resume != true) {
          await step.sleep(Duration(milliseconds: delayMs));
        }
        return true;
      });
      return flow.step(
        'finish',
        (_) => {
          ...prepared,
          'finishedAt': DateTime.now().toUtc().toIso8601String(),
        },
      );
    },
  ),
  WorkflowScript<Map<String, Object?>>(
    name: WorkbenchWorkflowKind.approval.descriptor.name,
    checkpoints: [
      WorkflowCheckpoint(name: 'draft'),
      WorkflowCheckpoint(name: 'approval'),
      WorkflowCheckpoint(name: 'release'),
    ],
    run: (flow) async {
      final draft = await flow.step<Map<String, Object?>>(
        'draft',
        (_) => {
          'runId': flow.runId,
          'title': 'Release a small report',
          'draftedAt': DateTime.now().toUtc().toIso8601String(),
        },
      );
      await flow.step('approval', (step) async {
        final event = step.takeResumeData();
        if (event is! Map || event['approved'] != true) {
          await step.awaitEvent(workflowApprovalTopic(flow.runId));
        }
        return true;
      });
      return flow.step('release', (_) => {...draft, 'approved': true});
    },
  ),
];

/// Attaches workflow storage and definitions, never a consumer or polling timer.
///
/// The caller owns [app]. Stop/join its worker before closing this wrapper,
/// then close the core app. Use one shared runner for these demo workflows.
Future<StemWorkflowApp> attachDemoWorkflows(
  StemApp app, {
  StemFlutterStorageLayout? layout,
}) async {
  final resolved =
      layout ?? await StemFlutterStorageLayout.applicationSupport();
  await StemFlutterSqlite.initialize();
  return StemWorkflowApp.create(
    stemApp: app,
    scripts: createDemoWorkflowScripts(),
    workerConfig: StemWorkerConfig(
      queue: queueName,
      subscription: RoutingSubscription.singleQueue(queueName),
    ),
    storeFactory: sqliteWorkflowStoreFactory(
      File('${resolved.root.path}/workflows.sqlite'),
    ),
  );
}

/// Scan overdue runs once, then freeze polling before a bounded worker admits
/// deliveries. Newly suspended runs are left for the host's next timed wakeup.
/// This prevents a late poll from enqueueing after an idle worker has stopped.
Future<void> prepareDemoWorkflowCallback(StemWorkflowApp workflows) async {
  await workflows.startRuntime();
  await workflows.runtime.dispose();
}

/// Earliest persisted timer; the application may schedule a reconciling wakeup.
///
/// This observes state only. It does not poll for due work or consume deliveries.
Future<DateTime?> earliestWorkflowWakeAt(StemWorkflowApp workflows) async {
  DateTime? earliest;
  var offset = 0;
  while (true) {
    final page = await workflows.store.listRuns(
      status: WorkflowStatus.suspended,
      limit: 100,
      offset: offset,
    );
    for (final run in page) {
      final resumeAt = run.resumeAt;
      if (resumeAt != null &&
          (earliest == null || resumeAt.isBefore(earliest))) {
        earliest = resumeAt;
      }
    }
    if (page.length < 100) return earliest;
    offset += page.length;
  }
}
