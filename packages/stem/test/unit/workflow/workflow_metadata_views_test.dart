import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('RunState metadata getters', () {
    test('exposes suspension metadata fields', () {
      final state = RunState(
        id: 'run-1',
        workflow: 'invoice',
        status: WorkflowStatus.suspended,
        cursor: 2,
        params: const {'tenant': 'acme'},
        createdAt: DateTime.utc(2026, 2, 25),
        waitTopic: 'invoice.approved',
        suspensionData: const {
          'type': 'event',
          'step': 'awaitApproval',
          'iteration': 3,
          'iterationStep': 'approval#3',
          'topic': 'invoice.approved',
          'suspendedAt': '2026-02-25T00:00:10Z',
          'requestedResumeAt': '2026-02-25T00:05:00Z',
          'policyDeadline': '2026-02-25T00:10:00Z',
          'payload': {'invoiceId': 'inv-1'},
          'deliveredAt': '2026-02-25T00:03:00Z',
        },
      );

      expect(state.isSuspended, isTrue);
      expect(state.suspensionType, equals('event'));
      expect(state.suspensionStep, equals('awaitApproval'));
      expect(state.suspensionIteration, equals(3));
      expect(state.suspensionIterationStep, equals('approval#3'));
      expect(state.waitEventTopic, equals('invoice.approved'));
      expect(state.suspendedAt, equals(DateTime.utc(2026, 2, 25, 0, 0, 10)));
      expect(
        state.requestedResumeAt,
        equals(DateTime.utc(2026, 2, 25, 0, 5)),
      );
      expect(
        state.suspensionPolicyDeadline,
        equals(DateTime.utc(2026, 2, 25, 0, 10)),
      );
      expect(
        state.suspensionDeliveredAt,
        equals(DateTime.utc(2026, 2, 25, 0, 3)),
      );
      expect(
        state.suspensionPayload,
        equals(const <String, Object?>{'invoiceId': 'inv-1'}),
      );
    });
  });

  group('Workflow watcher metadata getters', () {
    test('exposes watcher and resolution metadata', () {
      final watcher = WorkflowWatcher(
        runId: 'run-1',
        stepName: 'awaitApproval',
        topic: 'invoice.approved',
        createdAt: DateTime.utc(2026, 2, 25),
        deadline: DateTime.utc(2026, 2, 25, 0, 15),
        data: const {
          'type': 'event',
          'iteration': 2,
          'iterationStep': 'approval#2',
          'payload': {'invoiceId': 'inv-1'},
          'suspendedAt': '2026-02-25T00:01:00Z',
          'requestedResumeAt': '2026-02-25T00:02:00Z',
          'policyDeadline': '2026-02-25T00:15:00Z',
        },
      );
      final resolution = WorkflowWatcherResolution(
        runId: 'run-1',
        stepName: 'awaitApproval',
        topic: 'invoice.approved',
        resumeData: const {
          'type': 'event',
          'iteration': 2,
          'iterationStep': 'approval#2',
          'payload': {'invoiceId': 'inv-1'},
          'deliveredAt': '2026-02-25T00:01:30Z',
        },
      );

      expect(watcher.suspensionType, equals('event'));
      expect(watcher.iteration, equals(2));
      expect(watcher.iterationStep, equals('approval#2'));
      expect(watcher.payload, equals(const {'invoiceId': 'inv-1'}));
      expect(watcher.suspendedAt, equals(DateTime.utc(2026, 2, 25, 0, 1)));
      expect(
        watcher.requestedResumeAt,
        equals(DateTime.utc(2026, 2, 25, 0, 2)),
      );
      expect(
        watcher.policyDeadline,
        equals(DateTime.utc(2026, 2, 25, 0, 15)),
      );

      expect(resolution.suspensionType, equals('event'));
      expect(resolution.iteration, equals(2));
      expect(resolution.iterationStep, equals('approval#2'));
      expect(resolution.payload, equals(const {'invoiceId': 'inv-1'}));
      expect(
        resolution.deliveredAt,
        equals(DateTime.utc(2026, 2, 25, 0, 1, 30)),
      );
    });
  });
}
