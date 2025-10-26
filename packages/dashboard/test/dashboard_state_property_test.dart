import 'package:property_testing/property_testing.dart';
import 'package:stem/stem.dart' show DeadLetterEntry, DeadLetterReplayResult;
import 'package:stem_dashboard/src/stem/control_messages.dart';
import 'package:stem_dashboard/src/services/models.dart';
import 'package:stem_dashboard/src/services/stem_service.dart';
import 'package:stem_dashboard/src/state/dashboard_state.dart';
import 'package:test/test.dart';

class _QueueDeltaCase {
  _QueueDeltaCase({
    required this.queue,
    required this.pending1,
    required this.pending2,
    required this.inflight1,
    required this.inflight2,
    required this.dead1,
    required this.dead2,
  });

  final String queue;
  final int pending1;
  final int pending2;
  final int inflight1;
  final int inflight2;
  final int dead1;
  final int dead2;

  int get pendingDelta => pending2 - pending1;
  int get inflightDelta => inflight2 - inflight1;
  int get deadDelta => dead2 - dead1;

  List<QueueSummary> toSnapshots() => [
    QueueSummary(
      queue: queue,
      pending: pending1,
      inflight: inflight1,
      deadLetters: dead1,
    ),
    QueueSummary(
      queue: queue,
      pending: pending2,
      inflight: inflight2,
      deadLetters: dead2,
    ),
  ];
}

class _SequenceDashboardService implements DashboardDataSource {
  _SequenceDashboardService({
    required List<List<QueueSummary>> queueSnapshots,
    required List<List<WorkerStatus>> workerSnapshots,
  }) : _queueSnapshots = queueSnapshots,
       _workerSnapshots = workerSnapshots;

  final List<List<QueueSummary>> _queueSnapshots;
  final List<List<WorkerStatus>> _workerSnapshots;

  int _queueIndex = 0;
  int _workerIndex = 0;

  @override
  Future<List<QueueSummary>> fetchQueueSummaries() async {
    if (_queueSnapshots.isEmpty) return const [];
    if (_queueIndex >= _queueSnapshots.length) {
      return _queueSnapshots.last;
    }
    return _queueSnapshots[_queueIndex++];
  }

  @override
  Future<List<WorkerStatus>> fetchWorkerStatuses() async {
    if (_workerSnapshots.isEmpty) return const [];
    if (_workerIndex >= _workerSnapshots.length) {
      return _workerSnapshots.last;
    }
    return _workerSnapshots[_workerIndex++];
  }

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
  Future<List<ControlReplyMessage>> sendControlCommand(
    ControlCommandMessage command, {
    Duration timeout = const Duration(seconds: 5),
  }) async => const [];

  @override
  Future<void> close() async {}
}

void main() {
  final queueDeltaGen = Gen.string(minLength: 1, maxLength: 12).flatMap((
    queue,
  ) {
    return Gen.containerOf<List<int>, int>(
      Gen.integer(min: 0, max: 500),
      (values) => List<int>.from(values),
      minLength: 6,
      maxLength: 6,
    ).map(
      (values) => _QueueDeltaCase(
        queue: queue,
        pending1: values[0],
        pending2: values[1],
        inflight1: values[2],
        inflight2: values[3],
        dead1: values[4],
        dead2: values[5],
      ),
    );
  });

  test('DashboardState emits queue delta events', () async {
    final runner = PropertyTestRunner(queueDeltaGen, (sample) async {
      final snapshots = sample.toSnapshots();
      final service = _SequenceDashboardService(
        queueSnapshots: snapshots
            .map((summary) => [summary])
            .toList(growable: false),
        workerSnapshots: const [<WorkerStatus>[], <WorkerStatus>[]],
      );
      final state = DashboardState(
        service: service,
        pollInterval: const Duration(hours: 1),
      );

      await state.runOnce();
      await state.runOnce();

      if (sample.pendingDelta != 0) {
        final pendingEvent = state.events.firstWhere(
          (event) => event.title.contains('pending'),
        );
        expect(
          pendingEvent.title,
          contains(sample.pendingDelta > 0 ? 'increased' : 'decreased'),
        );
        expect(pendingEvent.summary, contains('${sample.pending1}'));
        expect(pendingEvent.summary, contains('${sample.pending2}'));
      }

      if (sample.inflightDelta != 0) {
        final inflightEvent = state.events.firstWhere(
          (event) => event.title.contains('inflight'),
        );
        expect(
          inflightEvent.title,
          contains(sample.inflightDelta > 0 ? 'increased' : 'decreased'),
        );
        expect(inflightEvent.summary, contains('${sample.inflight1}'));
        expect(inflightEvent.summary, contains('${sample.inflight2}'));
      }

      if (sample.deadDelta != 0) {
        final deadEvent = state.events.firstWhere(
          (event) => event.title.contains('dead letters'),
        );
        expect(
          deadEvent.title,
          contains(sample.deadDelta > 0 ? 'increased' : 'decreased'),
        );
        expect(deadEvent.summary, contains('${sample.dead1}'));
        expect(deadEvent.summary, contains('${sample.dead2}'));
      }

      await service.close();
      await state.dispose();
    }, PropertyConfig(numTests: 40));

    final result = await runner.run();
    expect(result.success, isTrue, reason: result.report);
  });
}
