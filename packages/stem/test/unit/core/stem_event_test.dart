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
  });
}
