import 'package:stem/src/workflow/core/event_bus.dart';
import 'package:stem/src/workflow/core/workflow_store.dart';

/// No-op [EventBus] suitable for single-process tests.
///
/// Notifications are short-circuited through the [WorkflowStore] since the
/// runtime already knows which runs are awaiting a topic.
class InMemoryEventBus implements EventBus {
  /// Creates an in-memory event bus bound to a [store].
  InMemoryEventBus(this.store);

  /// Workflow store used to resolve waiting runs.
  final WorkflowStore store;

  /// Simply drops the event because the runtime fetches waiting runs directly
  /// from the store.
  @override
  Future<void> emit(String topic, Map<String, Object?> payload) async {}

  /// Returns zero because there is no fan-out beyond the calling isolate.
  @override
  Future<int> fanout(String topic) async {
    return 0;
  }
}
