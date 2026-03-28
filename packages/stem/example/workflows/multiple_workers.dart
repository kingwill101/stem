// Demonstrates one workflow routing tasks to multiple dedicated worker queues.
// Run with: dart run example/workflows/multiple_workers.dart

import 'package:stem/stem.dart';

const String _workflowQueue = 'workflow';
const String _notificationsQueue = 'notifications';
const String _analyticsQueue = 'analytics';

final accountOnboardingFlow = Flow<Map<String, String>>(
  name: 'workflow.multi_workers',
  build: (flow) {
    flow.step('dispatch-to-workers', (ctx) async {
      final notifyTaskId = await ctx.enqueue(
        'notify.send',
        args: const {'email': 'alex@example.com'},
        enqueueOptions: const TaskEnqueueOptions(queue: _notificationsQueue),
      );
      final trackTaskId = await ctx.enqueue(
        'analytics.track',
        args: const {'userId': 'alex', 'event': 'account.created'},
        enqueueOptions: const TaskEnqueueOptions(queue: _analyticsQueue),
      );

      return <String, String>{
        'notifyTaskId': notifyTaskId,
        'trackTaskId': trackTaskId,
      };
    });
  },
);

class NotifyTask extends TaskHandler<String> {
  @override
  String get name => 'notify.send';

  @override
  TaskOptions get options => const TaskOptions(queue: _notificationsQueue);

  @override
  Future<String> call(TaskContext context, Map<String, Object?> args) async {
    final email = args['email'] as String? ?? 'unknown';
    print('[notifications worker] send notification -> $email');
    return 'notified:$email';
  }
}

class AnalyticsTask extends TaskHandler<String> {
  @override
  String get name => 'analytics.track';

  @override
  TaskOptions get options => const TaskOptions(queue: _analyticsQueue);

  @override
  Future<String> call(TaskContext context, Map<String, Object?> args) async {
    final userId = args['userId'] as String? ?? 'unknown';
    final event = args['event'] as String? ?? 'unknown';
    print('[analytics worker] track event "$event" for user "$userId"');
    return 'tracked:$event:$userId';
  }
}

Future<void> main() async {
  final client = await StemClient.inMemory();
  final workflowApp = await client.createWorkflowApp(
    flows: [accountOnboardingFlow],
    workerConfig: const StemWorkerConfig(queue: _workflowQueue),
  );
  await workflowApp.start();

  final notificationsWorker = await client.createWorker(
    workerConfig: StemWorkerConfig(
      queue: 'notifications-worker',
      consumerName: 'notifications-worker',
      subscription: RoutingSubscription.singleQueue(_notificationsQueue),
    ),
    tasks: [NotifyTask()],
  );
  final analyticsWorker = await client.createWorker(
    workerConfig: StemWorkerConfig(
      queue: 'analytics-worker',
      consumerName: 'analytics-worker',
      subscription: RoutingSubscription.singleQueue(_analyticsQueue),
    ),
    tasks: [AnalyticsTask()],
  );

  Future.wait([notificationsWorker.start(), analyticsWorker.start()]);

  final workflowResult = await accountOnboardingFlow.startAndWait(workflowApp);
  final taskIds = workflowResult?.value ?? const <String, String>{};
  final notifyResult = await workflowApp.waitForTask<String>(
    taskIds['notifyTaskId']!,
    timeout: const Duration(seconds: 5),
  );
  final trackResult = await workflowApp.waitForTask<String>(
    taskIds['trackTaskId']!,
    timeout: const Duration(seconds: 5),
  );

  print('workflow ${workflowResult?.runId} complete');
  print('notifier: ${notifyResult?.value}');
  print('analytics: ${trackResult?.value}');

  await Future.wait([
    notificationsWorker.shutdown(),
    analyticsWorker.shutdown(),
    workflowApp.close(),
    client.close(),
  ]);
}
