/// Persisted step checkpoint metadata for a workflow run.
class WorkflowStepEntry {
  /// Creates a workflow step entry snapshot.
  const WorkflowStepEntry({
    required this.name,
    required this.value,
    required this.position,
    this.completedAt,
  });

  /// Rehydrates a step entry from serialized JSON.
  factory WorkflowStepEntry.fromJson(Map<String, Object?> json) {
    return WorkflowStepEntry(
      name: json['name']?.toString() ?? '',
      value: json['value'],
      position: _intFromJson(json['position']),
      completedAt: _dateFromJson(json['completedAt']),
    );
  }

  /// Step identifier as registered in the workflow definition.
  final String name;

  /// Serialized checkpoint value captured after the step succeeded.
  final Object? value;

  /// Zero-based ordinal for rendering in execution order.
  final int position;

  /// Optional timestamp when the checkpoint was recorded.
  final DateTime? completedAt;

  /// Converts this entry to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return {
      'name': name,
      'value': value,
      'position': position,
      if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    };
  }
}

int _intFromJson(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _dateFromJson(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}
