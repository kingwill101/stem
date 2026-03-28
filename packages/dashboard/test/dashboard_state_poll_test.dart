import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart'
    show DeadLetterEntry, DeadLetterReplayResult, TaskState;
import 'package:stem_dashboard/src/services/models.dart';
import 'package:stem_dashboard/src/services/stem_service.dart';
import 'package:stem_dashboard/src/state/dashboard_state.dart';
import 'package:stem_dashboard/src/stem/control_messages.dart';
import 'package:test/test.dart';

class _FailingPollService implements DashboardDataSource {
  @override
  Future<List<QueueSummary>> fetchQueueSummaries() async {
    throw StateError('queue failed');
  }

  @override
  Future<List<WorkerStatus>> fetchWorkerStatuses() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    throw StateError('worker failed');
  }

  @override
  Future<List<DashboardTaskStatusEntry>> fetchTaskStatuses({
    TaskState? state,
    String? queue,
    int limit = 100,
    int offset = 0,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    throw StateError('tasks failed');
  }

  @override
  Future<DashboardTaskStatusEntry?> fetchTaskStatus(String taskId) async =>
      null;

  @override
  Future<List<DashboardTaskStatusEntry>> fetchTaskStatusesForRun(
    String runId, {
    int limit = 200,
  }) async => const [];

  @override
  Future<DashboardWorkflowRunSnapshot?> fetchWorkflowRun(String runId) async =>
      null;

  @override
  Future<List<DashboardWorkflowCheckpointSnapshot>> fetchWorkflowCheckpoints(
    String runId,
  ) async => const [];

  @override
  Future<void> enqueueTask(EnqueueRequest request) async {}

  @override
  Future<DeadLetterReplayResult> replayDeadLetters(
    String queue, {
    int limit = 50,
    bool dryRun = false,
  }) async =>
      const DeadLetterReplayResult(entries: <DeadLetterEntry>[], dryRun: false);

  @override
  Future<bool> replayTaskById(String taskId, {String? queue}) async => false;

  @override
  Future<bool> revokeTask(
    String taskId, {
    bool terminate = false,
    String? reason,
  }) async => false;

  @override
  Future<List<ControlReplyMessage>> sendControlCommand(
    ControlCommandMessage command, {
    Duration timeout = const Duration(seconds: 5),
  }) async => const [];

  @override
  Future<void> close() async {}
}

class _BacklogOnlyService implements DashboardDataSource {
  @override
  Future<List<QueueSummary>> fetchQueueSummaries() async => const [
    QueueSummary(queue: 'default', pending: 999, inflight: 0, deadLetters: 0),
  ];

  @override
  Future<List<WorkerStatus>> fetchWorkerStatuses() async => const [];

  @override
  Future<List<DashboardTaskStatusEntry>> fetchTaskStatuses({
    TaskState? state,
    String? queue,
    int limit = 100,
    int offset = 0,
  }) async => const [];

  @override
  Future<DashboardTaskStatusEntry?> fetchTaskStatus(String taskId) async =>
      null;

  @override
  Future<List<DashboardTaskStatusEntry>> fetchTaskStatusesForRun(
    String runId, {
    int limit = 200,
  }) async => const [];

  @override
  Future<DashboardWorkflowRunSnapshot?> fetchWorkflowRun(String runId) async =>
      null;

  @override
  Future<List<DashboardWorkflowCheckpointSnapshot>> fetchWorkflowCheckpoints(
    String runId,
  ) async => const [];

  @override
  Future<void> enqueueTask(EnqueueRequest request) async {}

  @override
  Future<DeadLetterReplayResult> replayDeadLetters(
    String queue, {
    int limit = 50,
    bool dryRun = false,
  }) async =>
      const DeadLetterReplayResult(entries: <DeadLetterEntry>[], dryRun: false);

  @override
  Future<bool> replayTaskById(String taskId, {String? queue}) async => false;

  @override
  Future<bool> revokeTask(
    String taskId, {
    bool terminate = false,
    String? reason,
  }) async => false;

  @override
  Future<List<ControlReplyMessage>> sendControlCommand(
    ControlCommandMessage command, {
    Duration timeout = const Duration(seconds: 5),
  }) async => const [];

  @override
  Future<void> close() async {}
}

void main() {
  test(
    'runOnce does not leak uncaught async errors when one poll call fails',
    () async {
      final uncaught = <Object>[];

      await runZonedGuarded(
        () async {
          final state = DashboardState(
            service: _FailingPollService(),
            pollInterval: const Duration(hours: 1),
          );

          await expectLater(state.runOnce(), throwsA(isA<StateError>()));
          await Future<void>.delayed(const Duration(milliseconds: 60));
          await state.dispose();
        },
        (error, stackTrace) {
          uncaught.add(error);
        },
      );

      expect(uncaught, isEmpty);
    },
  );

  test('alert webhook delivery times out and polling continues', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((_) {
      // Intentionally keep responses open to simulate a hanging endpoint.
    });

    final state = DashboardState(
      service: _BacklogOnlyService(),
      pollInterval: const Duration(hours: 1),
      alertWebhookUrls: ['http://127.0.0.1:${server.port}/alerts'],
      alertBacklogThreshold: 1,
    );

    final watch = Stopwatch()..start();
    await state.runOnce();
    watch.stop();

    expect(watch.elapsed, lessThan(const Duration(seconds: 7)));
    expect(
      state.auditEntries.any(
        (entry) =>
            entry.kind == 'alert' &&
            entry.status == 'error' &&
            (entry.summary?.contains('timed out') ?? false),
      ),
      isTrue,
    );

    await state.dispose();
  });
}
