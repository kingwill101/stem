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
