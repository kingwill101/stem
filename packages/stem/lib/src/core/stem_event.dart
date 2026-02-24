/// Shared base contract for events emitted across Stem components.
abstract interface class StemEvent {
  /// Canonical event name.
  String get eventName;

  /// Timestamp when the event occurred.
  DateTime get occurredAt;

  /// Event attributes for diagnostics/observability.
  Map<String, Object?> get attributes;
}
