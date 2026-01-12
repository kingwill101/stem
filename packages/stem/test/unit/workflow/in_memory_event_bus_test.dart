import 'package:stem/src/workflow/core/workflow_store.dart';
import 'package:stem/src/workflow/event_bus/in_memory_event_bus.dart';
import 'package:test/test.dart';

class _NoopWorkflowStore implements WorkflowStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('InMemoryEventBus emit is a no-op and fanout returns 0', () async {
    final bus = InMemoryEventBus(_NoopWorkflowStore());

    await bus.emit('topic', {'value': 1});
    final count = await bus.fanout('topic');

    expect(count, 0);
  });
}
