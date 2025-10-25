import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'package:stem_dashboard/src/server.dart';
import 'package:stem_dashboard/src/services/models.dart';
import 'package:stem_dashboard/src/services/stem_service.dart';
import 'package:stem_dashboard/src/state/dashboard_state.dart';
import 'package:stem_dashboard/src/stem/control_messages.dart';

class _RecordingService implements DashboardDataSource {
  _RecordingService({this.queues = const [], this.workers = const []});

  final List<QueueSummary> queues;
  final List<WorkerStatus> workers;

  EnqueueRequest? lastEnqueue;

  @override
  Future<List<QueueSummary>> fetchQueueSummaries() async => queues;

  @override
  Future<List<WorkerStatus>> fetchWorkerStatuses() async => workers;

  @override
  Future<void> enqueueTask(EnqueueRequest request) async {
    lastEnqueue = request;
  }

  @override
  Future<List<ControlReplyMessage>> sendControlCommand(
    ControlCommandMessage command, {
    Duration timeout = const Duration(seconds: 5),
  }) async => const [];

  @override
  Future<void> close() async {}
}

Future<TestClient> _buildClient(
  _RecordingService service,
  DashboardState state,
) async {
  await state.runOnce();
  final engine = buildDashboardEngine(service: service, state: state);
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
        QueueSummary(queue: 'critical', pending: 2, inflight: 0, deadLetters: 1),
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

  test('POST /tasks/enqueue delegates to DashboardDataSource', () async {
    final service = _RecordingService();
    final state = DashboardState(service: service);
    final client = await _buildClient(service, state);

    final response = await client.post(
      '/tasks/enqueue',
      'queue=alpha&task=demo.task&priority=3&maxRetries=2&payload=%7B%22foo%22%3A%22bar%22%7D',
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
}
