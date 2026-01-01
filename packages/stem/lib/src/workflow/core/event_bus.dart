/// Distributes external events to workflow runs.
abstract class EventBus {
  /// Emits a payload on the provided [topic].
  Future<void> emit(String topic, Map<String, Object?> payload);

  /// Notifies suspended runs waiting on [topic]. Returns the number of runs
  /// re-queued.
  Future<int> fanout(String topic);
}
