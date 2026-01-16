import 'package:stem/stem.dart';
import 'package:test/test.dart';

class _NoopWorkflowStore implements WorkflowStore {
  @override
  Future<void> cancel(String runId, {String? reason}) async {}

  @override
  Future<bool> claimRun(
    String runId, {
    required String ownerId,
    Duration leaseDuration = const Duration(seconds: 30),
  }) async => false;

  @override
  Future<String> createRun({
    required String workflow,
    required Map<String, Object?> params,
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) async => '';

  @override
  Future<List<String>> dueRuns(DateTime now, {int limit = 256}) async =>
      const [];

  @override
  Future<RunState?> get(String runId) async => null;

  @override
  Future<List<RunState>> listRuns({
    String? workflow,
    WorkflowStatus? status,
    int limit = 50,
    int offset = 0,
  }) async => const [];

  @override
  Future<List<String>> listRunnableRuns({
    DateTime? now,
    int limit = 50,
    int offset = 0,
  }) async => const [];

  @override
  Future<List<WorkflowStepEntry>> listSteps(String runId) async => const [];

  @override
  Future<List<WorkflowWatcher>> listWatchers(
    String topic, {
    int limit = 256,
  }) async => const [];

  @override
  Future<void> markCompleted(String runId, Object? result) async {}

  @override
  Future<void> markFailed(
    String runId,
    Object error,
    StackTrace stack, {
    bool terminal = false,
  }) async {}

  @override
  Future<void> markResumed(String runId, {Map<String, Object?>? data}) async {}

  @override
  Future<void> markRunning(String runId, {String? stepName}) async {}

  @override
  Future<T?> readStep<T>(String runId, String stepName) async => null;

  @override
  Future<void> registerWatcher(
    String runId,
    String stepName,
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
  }) async {}

  @override
  Future<void> releaseRun(String runId, {required String ownerId}) async {}

  @override
  Future<bool> renewRunLease(
    String runId, {
    required String ownerId,
    Duration leaseDuration = const Duration(seconds: 30),
  }) async => false;

  @override
  Future<List<WorkflowWatcherResolution>> resolveWatchers(
    String topic,
    Map<String, Object?> payload, {
    int limit = 256,
  }) async => const [];

  @override
  Future<void> rewindToStep(String runId, String stepName) async {}

  @override
  Future<List<String>> runsWaitingOn(String topic, {int limit = 256}) async =>
      const [];

  @override
  Future<void> saveStep<T>(String runId, String stepName, T value) async {}

  @override
  Future<void> suspendOnTopic(
    String runId,
    String stepName,
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
  }) async {}

  @override
  Future<void> suspendUntil(
    String runId,
    String stepName,
    DateTime when, {
    Map<String, Object?>? data,
  }) async {}
}

void main() {
  test('InMemoryEventBus emit is a no-op and fanout returns 0', () async {
    final bus = InMemoryEventBus(_NoopWorkflowStore());

    await bus.emit('topic', {'value': 1});
    final count = await bus.fanout('topic');

    expect(count, 0);
  });
}
