import 'package:stem/src/core/payload_codec.dart';

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

  /// Decodes the persisted checkpoint value with [codec], when present.
  TValue? valueAs<TValue>({required PayloadCodec<TValue> codec}) {
    final stored = value;
    if (stored == null) return null;
    return codec.decode(stored);
  }

  /// Decodes the persisted checkpoint value with a JSON decoder, when present.
  TValue? valueJson<TValue>({
    required TValue Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    final stored = value;
    if (stored == null) return null;
    return PayloadCodec<TValue>.json(
      decode: decode,
      typeName: typeName,
    ).decode(stored);
  }

  /// Decodes the persisted checkpoint value with a version-aware JSON decoder,
  /// when present.
  TValue? valueVersionedJson<TValue>({
    required int version,
    required TValue Function(Map<String, dynamic> payload, int version) decode,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    final stored = value;
    if (stored == null) return null;
    return PayloadCodec<TValue>.versionedJson(
      version: version,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: typeName,
    ).decode(stored);
  }

  /// Base step name without any auto-version suffix.
  String get baseName {
    final hashIndex = name.indexOf('#');
    if (hashIndex == -1) return name;
    return name.substring(0, hashIndex);
  }

  /// Parsed iteration suffix for auto-versioned checkpoints, if present.
  int? get iteration {
    final hashIndex = name.lastIndexOf('#');
    if (hashIndex == -1) return null;
    return int.tryParse(name.substring(hashIndex + 1));
  }

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
