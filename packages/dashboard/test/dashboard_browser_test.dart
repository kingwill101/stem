import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'package:server_testing/src/browser/browser_exception.dart';
import 'package:stem/stem.dart' show DeadLetterEntry, DeadLetterReplayResult;
import 'package:stem_dashboard/src/server.dart';
import 'package:stem_dashboard/src/services/models.dart';
import 'package:stem_dashboard/src/services/stem_service.dart';
import 'package:stem_dashboard/src/state/dashboard_state.dart';
import 'package:stem_dashboard/src/stem/control_messages.dart';

class _FakeDashboardService implements DashboardDataSource {
  _FakeDashboardService({
    required List<QueueSummary> queues,
    required List<WorkerStatus> workers,
  }) : _queues = queues,
       _workers = workers;

  List<QueueSummary> _queues;
  List<WorkerStatus> _workers;
  EnqueueRequest? lastEnqueue;
  final List<ControlCommandMessage> controlCommands = [];
  String? lastReplayQueue;
  int? lastReplayLimit;
  bool? lastReplayDryRun;
  DeadLetterReplayResult replayResult = const DeadLetterReplayResult(
    entries: <DeadLetterEntry>[],
    dryRun: false,
  );

  set queues(List<QueueSummary> values) {
    _queues = List.unmodifiable(values);
  }

  set workers(List<WorkerStatus> values) {
    _workers = List.unmodifiable(values);
  }

  @override
  Future<List<QueueSummary>> fetchQueueSummaries() async =>
      List<QueueSummary>.from(_queues);

  @override
  Future<List<WorkerStatus>> fetchWorkerStatuses() async =>
      List<WorkerStatus>.from(_workers);

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
  Future<List<ControlReplyMessage>> sendControlCommand(
    ControlCommandMessage command, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    controlCommands.add(command);
    return const [];
  }

  @override
  Future<void> close() async {}

  void reset() {
    lastEnqueue = null;
    controlCommands.clear();
    lastReplayQueue = null;
    lastReplayLimit = null;
    lastReplayDryRun = null;
    replayResult = const DeadLetterReplayResult(
      entries: <DeadLetterEntry>[],
      dryRun: false,
    );
  }
}

Future<void> main() async {
  final service = _FakeDashboardService(
    queues: const [
      QueueSummary(queue: 'default', pending: 42, inflight: 3, deadLetters: 1),
      QueueSummary(queue: 'critical', pending: 7, inflight: 1, deadLetters: 0),
    ],
    workers: [
      WorkerStatus(
        workerId: 'worker-1',
        namespace: 'stem',
        timestamp: DateTime.now().toUtc(),
        isolateCount: 2,
        inflight: 1,
        queues: const [WorkerQueueInfo(name: 'default', inflight: 1)],
      ),
    ],
  );

  final state = DashboardState(
    service: service,
    pollInterval: const Duration(minutes: 5),
  );
  await state.start();

  final engine = buildDashboardEngine(service: service, state: state);
  final handler = RoutedRequestHandler(engine, true);
  final port = await handler.startServer(port: 0);

  try {
    await testBootstrap(
      BrowserConfig(
        browserName: 'chromium',
        headless: true,
        baseUrl: 'http://127.0.0.1:$port',
      ),
    );
  } on BrowserException catch (error) {
    // CI runners without browser binaries (e.g., Ubuntu 24.04) do not have
    // Playwright downloads available yet. Rather than failing the entire
    // suite, surface a message and skip the browser tests.
    // Local environments that have browsers installed will run as usual.
    // ignore: avoid_print
    print('Skipping dashboard browser tests: $error');
    await handler.close();
    await state.dispose();
    await service.close();
    return;
  }

  tearDownAll(() async {
    await handler.close();
    await state.dispose();
    await service.close();
  });

  browserTest('overview renders metrics from backend', (browser) async {
    await browser.visit('/');
    await browser.waiter.waitFor('.cards');
    await browser.assertSee('Overview');
    await browser.assertSee('Queued');
    await browser.assertSee('42');
    await browser.assertSee('critical');
  });

  browserTest('tasks form enqueues payload', (browser) async {
    service.reset();

    await browser.visit('/tasks');
    await browser.waiter.waitFor('.enqueue-form');

    await browser.executeScript('''
return fetch('/tasks/enqueue', {
  method: 'POST',
  headers: {'Content-Type': 'application/x-www-form-urlencoded'},
  body: new URLSearchParams({
    queue: 'alpha',
    task: 'example.echo',
    priority: '4',
    maxRetries: '3',
    payload: '{"userId":123}'
  })
}).then(() => true);
''');

    await browser.waitUntil(() async => service.lastEnqueue != null);

    await browser.visit('/tasks?flash=queued');
    await browser.waiter.waitFor('.flash.success');
    expect(service.lastEnqueue, isNotNull);
    expect(service.lastEnqueue!.queue, 'alpha');
    expect(service.lastEnqueue!.task, 'example.echo');
    expect(service.lastEnqueue!.priority, 4);
    expect(service.lastEnqueue!.maxRetries, 3);
    expect(service.lastEnqueue!.args, {'userId': 123});
  });

  browserTest('workers control endpoint posts commands', (browser) async {
    service.reset();

    await browser.visit('/workers');
    await browser.waiter.waitFor('.control-panel');

    await browser.executeScript('''
return fetch('/workers/control', {
  method: 'POST',
  headers: {'Content-Type': 'application/x-www-form-urlencoded'},
  body: new URLSearchParams({worker: 'worker-1', action: 'pause'})
}).then(() => true);
''');

    await browser.waitUntil(() async => service.controlCommands.isNotEmpty);
    final command = service.controlCommands.single;
    expect(command.type, 'shutdown');
    expect(command.targets, ['worker-1']);
    expect(command.payload['mode'], 'soft');
  });

  browserTest('queue replay form replays dead letters', (browser) async {
    service.reset();

    await browser.visit('/workers');
    await browser.waiter.waitFor('.table-card');

    await browser.executeScript('''
return fetch('/queues/replay', {
  method: 'POST',
  headers: {'Content-Type': 'application/x-www-form-urlencoded'},
  body: new URLSearchParams({queue: 'default', limit: '5'})
}).then(() => true);
''');

    await browser.waitUntil(() async => service.lastReplayQueue != null);
    expect(service.lastReplayQueue, 'default');
    expect(service.lastReplayLimit, 5);
    expect(service.lastReplayDryRun, isFalse);
  });
}
