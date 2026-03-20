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
      expect(
        state.suspensionPayloadJson<_InvoicePayload>(
          decode: _InvoicePayload.fromJson,
        ),
        isA<_InvoicePayload>().having(
          (value) => value.invoiceId,
          'invoiceId',
          'inv-1',
        ),
      );
      expect(
        state.suspensionPayloadVersionedJson<_InvoicePayload>(
          version: 2,
          decode: _InvoicePayload.fromVersionedJson,
        ),
        isA<_InvoicePayload>().having(
          (value) => value.invoiceId,
          'invoiceId',
          'inv-1',
        ),
      );
    });

    test('exposes runtime queue and serialization metadata', () {
      final state = RunState(
        id: 'run-2',
        workflow: 'invoice',
        status: WorkflowStatus.running,
        cursor: 1,
        params: const {
          'tenant': 'acme',
          '__stem.workflow.runtime': {
            'workflowId': 'abc123',
            'orchestrationQueue': 'workflow',
            'continuationQueue': 'workflow-continue',
            'executionQueue': 'workflow-step',
            'serializationFormat': 'json',
            'serializationVersion': '1',
            'frameFormat': 'stem-envelope',
            'frameVersion': '1',
            'encryptionScope': 'signed-envelope',
            'encryptionEnabled': true,
            'streamId': 'invoice_run-2',
          },
        },
        createdAt: DateTime.utc(2026, 2, 25),
      );

      expect(state.workflowParams, equals(const {'tenant': 'acme'}));
      expect(state.orchestrationQueue, equals('workflow'));
      expect(state.continuationQueue, equals('workflow-continue'));
      expect(state.executionQueue, equals('workflow-step'));
      expect(state.serializationFormat, equals('json'));
      expect(state.serializationVersion, equals('1'));
      expect(state.frameFormat, equals('stem-envelope'));
      expect(state.frameVersion, equals('1'));
      expect(state.encryptionScope, equals('signed-envelope'));
      expect(state.encryptionEnabled, isTrue);
      expect(state.streamId, equals('invoice_run-2'));
    });

    test('decodes raw result payloads as DTOs', () {
      final state = RunState(
        id: 'run-3',
        workflow: 'invoice',
        status: WorkflowStatus.completed,
        cursor: 2,
        params: const {'tenant': 'acme'},
        createdAt: DateTime.utc(2026, 2, 25),
        result: const {'invoiceId': 'inv-2'},
      );

      expect(
        state.resultJson<_InvoicePayload>(
          decode: _InvoicePayload.fromJson,
        ),
        isA<_InvoicePayload>().having(
          (value) => value.invoiceId,
          'invoiceId',
          'inv-2',
        ),
      );
      expect(
        state.resultVersionedJson<_InvoicePayload>(
          version: 2,
          decode: _InvoicePayload.fromVersionedJson,
        ),
        isA<_InvoicePayload>().having(
          (value) => value.invoiceId,
          'invoiceId',
          'inv-2',
        ),
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
      expect(
        watcher.payloadJson<_InvoicePayload>(
          decode: _InvoicePayload.fromJson,
        ),
        isA<_InvoicePayload>().having(
          (value) => value.invoiceId,
          'invoiceId',
          'inv-1',
        ),
      );
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
        resolution.payloadJson<_InvoicePayload>(
          decode: _InvoicePayload.fromJson,
        ),
        isA<_InvoicePayload>().having(
          (value) => value.invoiceId,
          'invoiceId',
          'inv-1',
        ),
      );
      expect(
        resolution.deliveredAt,
        equals(DateTime.utc(2026, 2, 25, 0, 1, 30)),
      );
    });
  });

  group('WorkflowStepEntry metadata getters', () {
    test('parses base name and iteration suffix', () {
      const step = WorkflowStepEntry(
        name: 'approval#3',
        value: {'invoiceId': 'inv-3'},
        position: 2,
      );
      const plain = WorkflowStepEntry(
        name: 'finalize',
        value: null,
        position: 3,
      );

      expect(step.baseName, equals('approval'));
      expect(step.iteration, equals(3));
      expect(
        step.valueJson<_InvoicePayload>(
          decode: _InvoicePayload.fromJson,
        ),
        isA<_InvoicePayload>().having(
          (value) => value.invoiceId,
          'invoiceId',
          'inv-3',
        ),
      );
      expect(plain.baseName, equals('finalize'));
      expect(plain.iteration, isNull);
    });
  });

  group('Workflow view decode helpers', () {
    test('decodes run results and suspension payloads as DTOs', () {
      final state = RunState(
        id: 'run-view-1',
        workflow: 'invoice',
        status: WorkflowStatus.suspended,
        cursor: 2,
        params: const {'tenant': 'acme'},
        createdAt: DateTime.utc(2026, 2, 25),
        result: const {'invoiceId': 'inv-4'},
        suspensionData: const {
          'type': 'event',
          'payload': {'invoiceId': 'inv-5'},
        },
      );
      final view = WorkflowRunView.fromState(state);

      expect(
        view.resultJson<_InvoicePayload>(decode: _InvoicePayload.fromJson),
        isA<_InvoicePayload>().having(
          (value) => value.invoiceId,
          'invoiceId',
          'inv-4',
        ),
      );
      expect(
        view.suspensionPayloadJson<_InvoicePayload>(
          decode: _InvoicePayload.fromJson,
        ),
        isA<_InvoicePayload>().having(
          (value) => value.invoiceId,
          'invoiceId',
          'inv-5',
        ),
      );
    });

    test('decodes checkpoint values as DTOs', () {
      const entry = WorkflowStepEntry(
        name: 'approval#1',
        value: {'invoiceId': 'inv-6'},
        position: 1,
      );
      final view = WorkflowCheckpointView.fromEntry(
        runId: 'run-view-2',
        workflow: 'invoice',
        entry: entry,
      );

      expect(
        view.valueJson<_InvoicePayload>(decode: _InvoicePayload.fromJson),
        isA<_InvoicePayload>().having(
          (value) => value.invoiceId,
          'invoiceId',
          'inv-6',
        ),
      );
    });
  });
}

class _InvoicePayload {
  const _InvoicePayload({required this.invoiceId});

  factory _InvoicePayload.fromJson(Map<String, dynamic> json) {
    return _InvoicePayload(invoiceId: json['invoiceId'] as String);
  }

  factory _InvoicePayload.fromVersionedJson(
    Map<String, dynamic> json,
    int version,
  ) {
    expect(version, 2);
    return _InvoicePayload(invoiceId: json['invoiceId'] as String);
  }

  final String invoiceId;
}
