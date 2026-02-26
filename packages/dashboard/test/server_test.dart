import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'package:stem/stem.dart'
    show DeadLetterEntry, DeadLetterReplayResult, Envelope, TaskState;
import 'package:stem_dashboard/src/server.dart';
import 'package:stem_dashboard/src/services/models.dart';
import 'package:stem_dashboard/src/services/stem_service.dart';
import 'package:stem_dashboard/src/state/dashboard_state.dart';
import 'package:stem_dashboard/src/stem/control_messages.dart';

class _RecordingService implements DashboardDataSource {
  _RecordingService({
    this.queues = const [],
    this.workers = const [],
    this.taskStatuses = const [],
  });

  final List<QueueSummary> queues;
  final List<WorkerStatus> workers;
  final List<DashboardTaskStatusEntry> taskStatuses;

  EnqueueRequest? lastEnqueue;
  final List<ControlCommandMessage> controlCommands = [];
  List<ControlReplyMessage> controlReplies = const [];
  String? lastReplayQueue;
  int? lastReplayLimit;
  bool? lastReplayDryRun;
  String? lastReplayTaskId;
  String? lastRevokeTaskId;
  bool? lastRevokeTerminate;
  String? lastRevokeReason;
  bool replayTaskSuccess = true;
  bool revokeTaskSuccess = true;
  DeadLetterReplayResult replayResult = const DeadLetterReplayResult(
    entries: <DeadLetterEntry>[],
    dryRun: false,
  );

  @override
  Future<List<QueueSummary>> fetchQueueSummaries() async => queues;

  @override
  Future<List<WorkerStatus>> fetchWorkerStatuses() async => workers;

  @override
  Future<List<DashboardTaskStatusEntry>> fetchTaskStatuses({
    TaskState? state,
    String? queue,
    int limit = 100,
    int offset = 0,
  }) async {
    final filtered = taskStatuses
        .where((entry) {
          if (state != null && entry.state != state) {
            return false;
          }
          if (queue != null &&
              queue.trim().isNotEmpty &&
              entry.queue != queue) {
            return false;
          }
          return true;
        })
        .skip(offset)
        .take(limit);
    return filtered.toList(growable: false);
  }

  @override
  Future<DashboardTaskStatusEntry?> fetchTaskStatus(String taskId) async {
    for (final entry in taskStatuses) {
      if (entry.id == taskId) {
        return entry;
      }
    }
    return null;
  }

  @override
  Future<List<DashboardTaskStatusEntry>> fetchTaskStatusesForRun(
    String runId, {
    int limit = 200,
  }) async {
    final filtered = taskStatuses
        .where((entry) => entry.runId == runId)
        .take(limit)
        .toList(growable: false);
    return filtered;
  }

  @override
  Future<DashboardWorkflowRunSnapshot?> fetchWorkflowRun(String runId) async =>
      null;

  @override
  Future<List<DashboardWorkflowStepSnapshot>> fetchWorkflowSteps(
    String runId,
  ) async => const [];

  @override
  Future<void> enqueueTask(EnqueueRequest request) async {
    lastEnqueue = request;
  }

  @override
  Future<DeadLetterReplayResult> replayDeadLetters(
    String queue, {
    int limit = 50,
    bool dryRun = false,
  }) async {
    lastReplayQueue = queue;
    lastReplayLimit = limit;
    lastReplayDryRun = dryRun;
    return replayResult;
  }

  @override
  Future<bool> replayTaskById(String taskId, {String? queue}) async {
    lastReplayTaskId = taskId;
    if (queue != null && queue.isNotEmpty) {
      lastReplayQueue = queue;
    }
    return replayTaskSuccess;
  }

  @override
  Future<bool> revokeTask(
    String taskId, {
    bool terminate = false,
    String? reason,
  }) async {
    lastRevokeTaskId = taskId;
    lastRevokeTerminate = terminate;
    lastRevokeReason = reason;
    return revokeTaskSuccess;
  }

  @override
  Future<List<ControlReplyMessage>> sendControlCommand(
    ControlCommandMessage command, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    controlCommands.add(command);
    return controlReplies;
  }

  @override
  Future<void> close() async {}
}

Future<TestClient> _buildClient(
  _RecordingService service,
  DashboardState state, {
  String basePath = '',
}) async {
  await state.runOnce();
  final engine = buildDashboardEngine(
    service: service,
    state: state,
    basePath: basePath,
  );
  final handler = RoutedRequestHandler(engine, true);
  addTearDown(() async {
    await handler.close();
    await state.dispose();
    await service.close();
  });
  return TestClient.inMemory(handler);
}

void main() {
  test('GET / renders overview metrics', () async {
    final service = _RecordingService(
      queues: const [
        QueueSummary(queue: 'default', pending: 5, inflight: 1, deadLetters: 0),
        QueueSummary(
          queue: 'critical',
          pending: 2,
          inflight: 0,
          deadLetters: 1,
        ),
      ],
    );
    final state = DashboardState(service: service);
    final client = await _buildClient(service, state);

    final response = await client.get('/');
    response
      ..assertStatus(200)
      ..assertBodyContains('Overview')
      ..assertBodyContains('default')
      ..assertBodyContains('critical');
  });

  test('GET /partials/overview renders turbo stream section updates', () async {
    final service = _RecordingService(
      queues: const [
        QueueSummary(queue: 'default', pending: 2, inflight: 1, deadLetters: 0),
      ],
      workers: [
        WorkerStatus(
          workerId: 'worker-1',
          namespace: 'stem',
          timestamp: DateTime.utc(2026),
          inflight: 1,
          isolateCount: 2,
          queues: const <WorkerQueueInfo>[],
        ),
      ],
      taskStatuses: [
        DashboardTaskStatusEntry(
          id: 'task-1',
          state: TaskState.running,
          attempt: 0,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026, 1, 1, 0, 1),
          queue: 'default',
          taskName: 'demo.run',
        ),
      ],
    );
    final state = DashboardState(service: service);
    final client = await _buildClient(service, state);

    final response = await client.get(
      '/partials/overview',
      headers: {
        'accept': ['text/vnd.turbo-stream.html'],
      },
    );
    response
      ..assertStatus(200)
      ..assertBodyContains(
        '<turbo-stream action="replace" target="overview-metrics"',
      )
      ..assertBodyContains(
        '<turbo-stream action="replace" target="overview-queue-table"',
      )
      ..assertBodyContains(
        '<turbo-stream action="replace" target="overview-latency-table"',
      )
      ..assertBodyContains(
        '<turbo-stream action="replace" target="overview-recent-tasks"',
      );
  });

  test('GET /tasks?flash=queued shows success banner', () async {
    final service = _RecordingService(
      queues: const [
        QueueSummary(queue: 'alpha', pending: 1, inflight: 0, deadLetters: 0),
      ],
    );
    final state = DashboardState(service: service);
    final client = await _buildClient(service, state);

    final response = await client.get('/tasks?flash=queued');
    response
      ..assertStatus(200)
      ..assertBodyContains('Task enqueued successfully.')
      ..assertBodyContains('Tracked queues');
  });

  test('GET /tasks renders recent task statuses', () async {
    final service = _RecordingService(
      queues: const [
        QueueSummary(queue: 'alpha', pending: 2, inflight: 1, deadLetters: 0),
      ],
      taskStatuses: [
        DashboardTaskStatusEntry(
          id: 'task-1',
          state: TaskState.failed,
          attempt: 2,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026, 1, 1, 0, 1),
          queue: 'alpha',
          taskName: 'demo.fail',
          errorMessage: 'boom',
        ),
      ],
    );
    final state = DashboardState(service: service);
    final client = await _buildClient(service, state);

    final response = await client.get('/tasks?state=failed');
    response
      ..assertStatus(200)
      ..assertBodyContains('Recent statuses with terminal failures.')
      ..assertBodyContains('task-1')
      ..assertBodyContains('data-task-row="task-1"')
      ..assertBodyContains('Open full detail')
      ..assertBodyContains('demo.fail')
      ..assertBodyContains('Failed')
      ..assertBodyContains('boom');
  });

  test(
    'GET /tasks paginates task status results via page and pageSize',
    () async {
      final statuses = List<DashboardTaskStatusEntry>.generate(55, (index) {
        final position = index + 1;
        return DashboardTaskStatusEntry(
          id: 'task-$position',
          state: TaskState.succeeded,
          attempt: 0,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026, 1, 1, 0, position),
          queue: 'alpha',
          taskName: 'demo.task.$position',
        );
      });
      final service = _RecordingService(
        queues: const [
          QueueSummary(queue: 'alpha', pending: 0, inflight: 0, deadLetters: 0),
        ],
        taskStatuses: statuses,
      );
      final state = DashboardState(service: service);
      final client = await _buildClient(service, state);

      final response = await client.get('/tasks?page=2&pageSize=25');
      response
        ..assertStatus(200)
        ..assertBodyContains('Page 2')
        ..assertBodyContains('task-26')
        ..assertBodyContains('Previous')
        ..assertBodyContains('Next');
    },
  );

  test('GET /tasks applies namespace/task/run filters', () async {
    final service = _RecordingService(
      queues: const [
        QueueSummary(queue: 'alpha', pending: 0, inflight: 0, deadLetters: 0),
      ],
      taskStatuses: [
        DashboardTaskStatusEntry(
          id: 'task-a',
          state: TaskState.running,
          attempt: 0,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026, 1, 1, 0, 1),
          queue: 'alpha',
          taskName: 'greeting.send',
          runId: 'run-1',
          meta: const {'namespace': 'stem'},
        ),
        DashboardTaskStatusEntry(
          id: 'task-b',
          state: TaskState.running,
          attempt: 0,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026, 1, 1, 0, 2),
          queue: 'alpha',
          taskName: 'greeting.send',
          runId: 'run-2',
          meta: const {'namespace': 'tenant-a'},
        ),
      ],
    );
    final state = DashboardState(service: service);
    final client = await _buildClient(service, state);

    final response = await client.get(
      '/tasks?namespace=tenant-a&task=greeting&runId=run-2',
    );
    response
      ..assertStatus(200)
      ..assertBodyContains('task-b');
    expect(response.body, isNot(contains('task-a')));
  });

  test('GET /namespaces renders namespace rollup table', () async {
    final service = _RecordingService(
      queues: const [
        QueueSummary(queue: 'alpha', pending: 2, inflight: 1, deadLetters: 0),
      ],
      workers: [
        WorkerStatus(
          workerId: 'worker-1',
          namespace: 'stem',
          timestamp: DateTime.utc(2026),
          isolateCount: 2,
          inflight: 1,
          queues: const [WorkerQueueInfo(name: 'alpha', inflight: 1)],
        ),
      ],
      taskStatuses: [
        DashboardTaskStatusEntry(
          id: 'task-ns-1',
          state: TaskState.running,
          attempt: 0,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026, 1, 1, 0, 1),
          queue: 'alpha',
          taskName: 'demo.task',
          meta: const {'namespace': 'stem'},
        ),
      ],
    );
    final state = DashboardState(service: service);
    final client = await _buildClient(service, state);

    final response = await client.get('/namespaces');
    response
      ..assertStatus(200)
      ..assertBodyContains('Namespaces')
      ..assertBodyContains('Namespace Summary')
      ..assertBodyContains('stem');
  });

  test('GET /workflows renders workflow run summaries', () async {
    final service = _RecordingService(
      taskStatuses: [
        DashboardTaskStatusEntry(
          id: 'task-wf-1',
          state: TaskState.running,
          attempt: 0,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026, 1, 1, 0, 1),
          queue: 'alpha',
          taskName: 'workflow.step',
          runId: 'run-xyz',
          workflowName: 'greetingFlow',
          workflowStep: 'stepA',
        ),
      ],
    );
    final state = DashboardState(service: service);
    final client = await _buildClient(service, state);

    final response = await client.get('/workflows');
    response
      ..assertStatus(200)
      ..assertBodyContains('Workflow Runs')
      ..assertBodyContains('run-xyz')
      ..assertBodyContains('greetingFlow');
  });

  test('GET /jobs renders job family summary', () async {
    final service = _RecordingService(
      taskStatuses: [
        DashboardTaskStatusEntry(
          id: 'task-job-1',
          state: TaskState.failed,
          attempt: 1,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026, 1, 1, 0, 1),
          queue: 'alpha',
          taskName: 'greeting.send',
          errorMessage: 'boom',
        ),
      ],
    );
    final state = DashboardState(service: service);
    final client = await _buildClient(service, state);

    final response = await client.get('/jobs');
    response
      ..assertStatus(200)
      ..assertBodyContains('Job Summary')
      ..assertBodyContains('greeting.send');
  });

  test('GET /tasks/inline renders lazy task panel as turbo stream', () async {
    final service = _RecordingService(
      taskStatuses: [
        DashboardTaskStatusEntry(
          id: 'task-inline-1',
          state: TaskState.failed,
          attempt: 1,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026, 1, 1, 0, 1),
          queue: 'alpha',
          taskName: 'demo.inline',
          errorMessage: 'boom',
          meta: const {'stem.task': 'demo.inline'},
        ),
      ],
    );
    final state = DashboardState(service: service);
    final client = await _buildClient(service, state);

    final response = await client.get(
      '/tasks/inline?id=task-inline-1&target=task-inline-task-inline-1',
      headers: {
        'accept': ['text/vnd.turbo-stream.html'],
      },
    );
    response
      ..assertStatus(200)
      ..assertBodyContains('<turbo-stream action="replace"')
      ..assertBodyContains('target="task-inline-task-inline-1"')
      ..assertBodyContains('demo.inline');
  });

  test('GET /search renders query results and saved views', () async {
    final service = _RecordingService(
      queues: const [
        QueueSummary(
          queue: 'critical',
          pending: 4,
          inflight: 1,
          deadLetters: 2,
        ),
      ],
      workers: [
        WorkerStatus(
          workerId: 'worker-a',
          namespace: 'stem',
          timestamp: DateTime.now().toUtc(),
          isolateCount: 2,
          inflight: 1,
          queues: const [WorkerQueueInfo(name: 'critical', inflight: 1)],
        ),
      ],
      taskStatuses: [
        DashboardTaskStatusEntry(
          id: 'task-abc',
          state: TaskState.failed,
          attempt: 1,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026, 1, 1, 0, 1),
          queue: 'critical',
          taskName: 'demo.fail',
          errorMessage: 'boom',
        ),
      ],
    );
    final state = DashboardState(service: service);
    final client = await _buildClient(service, state);

    final response = await client.get('/search?q=critical&scope=all');
    response
      ..assertStatus(200)
      ..assertBodyContains('Search')
      ..assertBodyContains('Saved Views')
      ..assertBodyContains('task-abc')
      ..assertBodyContains('worker-a');
  });

  test('GET /audit renders operator/audit entries', () async {
    final service = _RecordingService();
    final state = DashboardState(service: service)
      ..recordAudit(
        kind: 'action',
        action: 'task.replay',
        status: 'ok',
        actor: 'dashboard',
        summary: 'Replayed task-1',
      );
    final client = await _buildClient(service, state);

    final response = await client.get('/audit');
    response
      ..assertStatus(200)
      ..assertBodyContains('Audit Log')
      ..assertBodyContains('task.replay')
      ..assertBodyContains('Replayed task-1');
  });

  test('mount path prefixes routes, links, and redirects', () async {
    final service = _RecordingService();
    final state = DashboardState(service: service);
    final client = await _buildClient(service, state, basePath: '/dashboard');

    final page = await client.get('/dashboard');
    page
      ..assertStatus(200)
      ..assertBodyContains('href="/dashboard/tasks"')
      ..assertBodyContains(
        '/dashboard/dash/streams?topic=stem-dashboard:events',
      );

    final enqueue = await client.post(
      '/dashboard/tasks/enqueue',
      'queue=alpha&task=demo.task',
      headers: {
        'content-type': ['application/x-www-form-urlencoded'],
      },
    );

    enqueue
      ..assertStatus(303)
      ..assertHeader('location', '/dashboard/tasks?flash=queued');
  });

  test('POST /tasks/action cancel delegates revoke request', () async {
    final service = _RecordingService();
    final state = DashboardState(service: service);
    final client = await _buildClient(service, state);

    final response = await client.post(
      '/tasks/action',
      'action=cancel&taskId=task-1&queue=default&reason=manual',
      headers: {
        'content-type': ['application/x-www-form-urlencoded'],
      },
    );

    response.assertStatus(303);
    expect(service.lastRevokeTaskId, 'task-1');
    expect(service.lastRevokeTerminate, isFalse);
    expect(service.lastRevokeReason, 'manual');
  });

  test(
    'POST /tasks/action replay delegates dead-letter replay by id',
    () async {
      final service = _RecordingService();
      final state = DashboardState(service: service);
      final client = await _buildClient(service, state);

      final response = await client.post(
        '/tasks/action',
        'action=replay&taskId=task-1&queue=critical',
        headers: {
          'content-type': ['application/x-www-form-urlencoded'],
        },
      );

      response.assertStatus(303);
      expect(service.lastReplayTaskId, 'task-1');
      expect(service.lastReplayQueue, 'critical');
    },
  );

  test('GET /tasks/detail renders task detail and workflow timeline', () async {
    final service = _RecordingService(
      taskStatuses: [
        DashboardTaskStatusEntry(
          id: 'task-1',
          state: TaskState.failed,
          attempt: 2,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026, 1, 1, 0, 1),
          queue: 'alpha',
          taskName: 'demo.fail',
          errorMessage: 'boom',
          runId: 'run-1',
          workflowName: 'wf.demo',
          workflowStep: 'stepA',
        ),
        DashboardTaskStatusEntry(
          id: 'task-2',
          state: TaskState.running,
          attempt: 1,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026, 1, 1, 0, 2),
          queue: 'alpha',
          taskName: 'demo.next',
          runId: 'run-1',
          workflowName: 'wf.demo',
          workflowStep: 'stepB',
        ),
      ],
    );
    final state = DashboardState(service: service);
    final client = await _buildClient(service, state);

    final response = await client.get('/tasks/detail?id=task-1');
    response
      ..assertStatus(200)
      ..assertBodyContains('Task Detail')
      ..assertBodyContains('task-1')
      ..assertBodyContains('wf.demo')
      ..assertBodyContains('stepA')
      ..assertBodyContains('task-2');
  });

  test('GET /failures renders grouped diagnostics', () async {
    final service = _RecordingService(
      taskStatuses: [
        DashboardTaskStatusEntry(
          id: 'f-1',
          state: TaskState.failed,
          attempt: 1,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          queue: 'critical',
          taskName: 'demo.fail',
          errorType: 'StateError',
          errorMessage: 'boom',
        ),
      ],
    );
    final state = DashboardState(service: service);
    final client = await _buildClient(service, state);

    final response = await client.get('/failures');
    response
      ..assertStatus(200)
      ..assertBodyContains('Failure Diagnostics')
      ..assertBodyContains('critical')
      ..assertBodyContains('Replay DLQ');
  });

  test('POST /tasks/enqueue delegates to DashboardDataSource', () async {
    final service = _RecordingService();
    final state = DashboardState(service: service);
    final client = await _buildClient(service, state);

    final response = await client.post(
      '/tasks/enqueue',
      'queue=alpha&task=demo.task&priority=3&maxRetries=2&payload='
          '%7B%22foo%22%3A%22bar%22%7D',
      headers: {
        'content-type': ['application/x-www-form-urlencoded'],
      },
    );

    response
      ..assertStatus(303)
      ..assertHeader('location', '/tasks?flash=queued');

    final recorded = service.lastEnqueue;
    expect(recorded, isNotNull);
    expect(recorded!.queue, 'alpha');
    expect(recorded.task, 'demo.task');
    expect(recorded.priority, 3);
    expect(recorded.maxRetries, 2);
    expect(recorded.args, {'foo': 'bar'});
  });

  test('GET /events renders placeholder when no activity', () async {
    final service = _RecordingService();
    final state = DashboardState(service: service);
    final client = await _buildClient(service, state);

    final response = await client.get('/events');
    response
      ..assertStatus(200)
      ..assertBodyContains('No events captured yet');
  });

  test('POST /workers/control dispatches ping to targeted worker', () async {
    final service = _RecordingService(
      workers: [
        WorkerStatus(
          workerId: 'worker-1',
          namespace: 'stem',
          timestamp: DateTime.now().toUtc(),
          isolateCount: 1,
          inflight: 0,
          queues: const [],
        ),
      ],
    );
    final state = DashboardState(service: service);
    final client = await _buildClient(service, state);

    final response = await client.post(
      '/workers/control',
      'worker=worker-1&action=ping',
      headers: {
        'content-type': ['application/x-www-form-urlencoded'],
      },
    );

    response.assertStatus(303);
    expect(response.headers['location'], anything);
    expect(service.controlCommands, hasLength(1));
    final command = service.controlCommands.single;
    expect(command.type, 'ping');
    expect(command.targets, ['worker-1']);
    expect(command.timeoutMs, 5000);
  });

  test('POST /workers/control reports errors from replies', () async {
    final service = _RecordingService()
      ..controlReplies = [
        ControlReplyMessage(
          requestId: 'req',
          workerId: 'worker-1',
          status: 'error',
          error: const {'message': 'boom'},
        ),
      ];
    final state = DashboardState(service: service);
    final client = await _buildClient(service, state);

    final response = await client.post(
      '/workers/control',
      'worker=worker-1&action=shutdown',
      headers: {
        'content-type': ['application/x-www-form-urlencoded'],
      },
    );

    response.assertStatus(303);
    final errorLocation = response.headers['location']?.first;
    expect(errorLocation, isNotNull);
    expect(errorLocation, contains('error='));
    expect(service.controlCommands, hasLength(1));
    expect(service.controlCommands.single.type, 'shutdown');
  });

  test('POST /queues/replay forwards to dashboard service', () async {
    final service =
        _RecordingService(
            queues: const [
              QueueSummary(
                queue: 'default',
                pending: 0,
                inflight: 0,
                deadLetters: 3,
              ),
            ],
          )
          ..replayResult = DeadLetterReplayResult(
            entries: [
              DeadLetterEntry(
                envelope: Envelope(
                  id: 'dlq-1',
                  name: 'demo.task',
                  args: const {},
                ),
                reason: 'retry-limit',
                deadAt: DateTime.now().toUtc(),
              ),
            ],
            dryRun: false,
          );
    final state = DashboardState(service: service);
    final client = await _buildClient(service, state);

    final response = await client.post(
      '/queues/replay',
      'queue=default&limit=3',
      headers: {
        'content-type': ['application/x-www-form-urlencoded'],
      },
    );

    response.assertStatus(303);
    final location = response.headers['location']?.first;
    expect(location, isNotNull);
    expect(service.lastReplayQueue, 'default');
    expect(service.lastReplayLimit, 3);
    expect(service.lastReplayDryRun, isFalse);
  });

  test('POST /queues/replay supports dryRun flag', () async {
    final service = _RecordingService(
      queues: const [
        QueueSummary(
          queue: 'critical',
          pending: 0,
          inflight: 0,
          deadLetters: 8,
        ),
      ],
    );
    final state = DashboardState(service: service);
    final client = await _buildClient(service, state);

    final response = await client.post(
      '/queues/replay',
      'queue=critical&limit=20&dryRun=true',
      headers: {
        'content-type': ['application/x-www-form-urlencoded'],
      },
    );

    response.assertStatus(303);
    final dryRunLocation = response.headers['location']?.first;
    expect(dryRunLocation, isNotNull);
    expect(service.lastReplayQueue, 'critical');
    expect(service.lastReplayLimit, 20);
    expect(service.lastReplayDryRun, isTrue);
  });
}
