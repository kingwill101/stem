import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('StemEvent', () {
    test('WorkerEvent implements StemEvent contract', () {
      final event = WorkerEvent(type: WorkerEventType.completed);

      expect(event, isA<StemEvent>());
      expect(event.eventName, 'worker.completed');
      expect(event.occurredAt, isA<DateTime>());
      expect(event.attributes, isA<Map<String, Object?>>());
    });

    test('WorkerEvent exposes typed data helpers', () {
      final event = WorkerEvent(
        type: WorkerEventType.completed,
        data: const {
          'retry': {'delayMs': 250},
          PayloadCodec.versionKey: 2,
          'delayMs': 250,
        },
      );

      expect(event.dataValue<int>('delayMs'), 250);
      expect(event.dataValueOr<String>('missing', 'fallback'), 'fallback');
      expect(event.requiredDataValue<int>('delayMs'), 250);
      expect(
        event.dataJson<_RetryData>(decode: _RetryData.fromJson),
        isA<_RetryData>().having((value) => value.delayMs, 'delayMs', 250),
      );
      expect(
        event.dataVersionedJson<_RetryData>(
          version: 2,
          decode: _RetryData.fromVersionedJson,
        ),
        isA<_RetryData>().having((value) => value.delayMs, 'delayMs', 250),
      );
    });

    test('QueueCustomEvent implements StemEvent contract', () {
      final event = QueueCustomEvent(
        id: 'evt-1',
        queue: 'orders',
        name: 'order.created',
        payload: const {'id': 'o-1'},
        emittedAt: DateTime.utc(2026, 2, 24, 15),
      );

      expect(event, isA<StemEvent>());
      expect(event.eventName, 'order.created');
      expect(event.occurredAt, DateTime.utc(2026, 2, 24, 15));
      expect(event.attributes['queue'], 'orders');
    });

    test('WorkflowStepEvent implements StemEvent contract', () {
      final event = WorkflowStepEvent(
        runId: 'run-1',
        workflow: 'checkout',
        stepId: 'charge',
        type: WorkflowStepEventType.started,
        timestamp: DateTime.utc(2026, 2, 24, 16),
      );

      expect(event, isA<StemEvent>());
      expect(event.eventName, 'workflow.step.started');
      expect(event.occurredAt, DateTime.utc(2026, 2, 24, 16));
      expect(event.attributes['runId'], 'run-1');
      expect(event.attributes['stepId'], 'charge');
    });

    test('WorkflowStepEvent decodes DTO result payloads', () {
      final event = WorkflowStepEvent(
        runId: 'run-2',
        workflow: 'checkout',
        stepId: 'charge',
        type: WorkflowStepEventType.completed,
        timestamp: DateTime.utc(2026, 2, 24, 16, 30),
        result: const {'chargeId': 'ch_123'},
      );

      expect(
        event.resultJson<_ChargeResult>(decode: _ChargeResult.fromJson),
        isA<_ChargeResult>().having(
          (value) => value.chargeId,
          'chargeId',
          'ch_123',
        ),
      );
      expect(
        event.resultVersionedJson<_ChargeResult>(
          version: 2,
          decode: _ChargeResult.fromVersionedJson,
        ),
        isA<_ChargeResult>().having(
          (value) => value.chargeId,
          'chargeId',
          'ch_123',
        ),
      );
    });

    test('WorkflowStepEvent exposes typed metadata helpers', () {
      final event = WorkflowStepEvent(
        runId: 'run-3',
        workflow: 'checkout',
        stepId: 'charge',
        type: WorkflowStepEventType.completed,
        timestamp: DateTime.utc(2026, 2, 24, 16, 45),
        metadata: const {
          'worker': {
            PayloadCodec.versionKey: 2,
            'workerId': 'worker-1',
          },
          PayloadCodec.versionKey: 2,
          'workerId': 'worker-1',
        },
      );

      expect(event.metadataValue<Map<String, Object?>>('worker'), isNotNull);
      expect(
        event.metadataJson<_StepMetadata>(
          'worker',
          decode: _StepMetadata.fromJson,
        ),
        isA<_StepMetadata>().having(
          (value) => value.workerId,
          'workerId',
          'worker-1',
        ),
      );
      expect(
        event.metadataVersionedJson<_StepMetadata>(
          'worker',
          version: 2,
          decode: _StepMetadata.fromVersionedJson,
        ),
        isA<_StepMetadata>().having(
          (value) => value.workerId,
          'workerId',
          'worker-1',
        ),
      );
      expect(
        event.metadataPayloadJson<_StepMetadata>(
          decode: _StepMetadata.fromJson,
        ),
        isA<_StepMetadata>().having(
          (value) => value.workerId,
          'workerId',
          'worker-1',
        ),
      );
      expect(
        event.metadataPayloadVersionedJson<_StepMetadata>(
          version: 2,
          decode: _StepMetadata.fromVersionedJson,
        ),
        isA<_StepMetadata>().having(
          (value) => value.workerId,
          'workerId',
          'worker-1',
        ),
      );
    });

    test('WorkflowRuntimeEvent exposes typed metadata helpers', () {
      final event = WorkflowRuntimeEvent(
        runId: 'run-4',
        workflow: 'checkout',
        type: WorkflowRuntimeEventType.continuationEnqueued,
        timestamp: DateTime.utc(2026, 2, 24, 17),
        metadata: const {
          'detail': {
            PayloadCodec.versionKey: 2,
            'reason': 'resume',
          },
          PayloadCodec.versionKey: 2,
          'reason': 'resume',
        },
      );

      expect(
        event.metadataJson<_RuntimeMetadata>(
          'detail',
          decode: _RuntimeMetadata.fromJson,
        ),
        isA<_RuntimeMetadata>().having(
          (value) => value.reason,
          'reason',
          'resume',
        ),
      );
      expect(
        event.metadataVersionedJson<_RuntimeMetadata>(
          'detail',
          version: 2,
          decode: _RuntimeMetadata.fromVersionedJson,
        ),
        isA<_RuntimeMetadata>().having(
          (value) => value.reason,
          'reason',
          'resume',
        ),
      );
      expect(
        event.metadataPayloadJson<_RuntimeMetadata>(
          decode: _RuntimeMetadata.fromJson,
        ),
        isA<_RuntimeMetadata>().having(
          (value) => value.reason,
          'reason',
          'resume',
        ),
      );
      expect(
        event.metadataPayloadVersionedJson<_RuntimeMetadata>(
          version: 2,
          decode: _RuntimeMetadata.fromVersionedJson,
        ),
        isA<_RuntimeMetadata>().having(
          (value) => value.reason,
          'reason',
          'resume',
        ),
      );
    });
  });
}

class _ChargeResult {
  const _ChargeResult({required this.chargeId});

  factory _ChargeResult.fromJson(Map<String, dynamic> json) {
    return _ChargeResult(chargeId: json['chargeId'] as String);
  }

  factory _ChargeResult.fromVersionedJson(
    Map<String, dynamic> json,
    int version,
  ) {
    expect(version, 2);
    return _ChargeResult(chargeId: json['chargeId'] as String);
  }

  final String chargeId;
}

class _RetryData {
  const _RetryData({required this.delayMs});

  factory _RetryData.fromJson(Map<String, dynamic> json) {
    return _RetryData(delayMs: json['delayMs'] as int);
  }

  factory _RetryData.fromVersionedJson(
    Map<String, dynamic> json,
    int version,
  ) {
    expect(version, 2);
    return _RetryData.fromJson(json);
  }

  final int delayMs;
}

class _StepMetadata {
  const _StepMetadata({required this.workerId});

  factory _StepMetadata.fromJson(Map<String, dynamic> json) {
    return _StepMetadata(workerId: json['workerId'] as String);
  }

  factory _StepMetadata.fromVersionedJson(
    Map<String, dynamic> json,
    int version,
  ) {
    expect(version, 2);
    return _StepMetadata.fromJson(json);
  }

  final String workerId;
}

class _RuntimeMetadata {
  const _RuntimeMetadata({required this.reason});

  factory _RuntimeMetadata.fromJson(Map<String, dynamic> json) {
    return _RuntimeMetadata(reason: json['reason'] as String);
  }

  factory _RuntimeMetadata.fromVersionedJson(
    Map<String, dynamic> json,
    int version,
  ) {
    expect(version, 2);
    return _RuntimeMetadata.fromJson(json);
  }

  final String reason;
}
