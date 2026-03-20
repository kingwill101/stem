import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/payload_codec.dart';
import 'package:stem/src/core/stem.dart' show Stem;
import 'package:stem/stem.dart' show Stem;

/// Typed view over a [TaskStatus] returned by helpers such as
/// [Stem.waitForTask] or canvas typed operations.
class TaskResult<T extends Object?> {
  /// Creates a typed task result snapshot.
  const TaskResult({
    required this.taskId,
    required this.status,
    this.value,
    this.rawPayload,
    this.timedOut = false,
  });

  /// Logical task identifier.
  final String taskId;

  /// Latest status snapshot from the backend.
  final TaskStatus status;

  /// Decoded payload when the task succeeded.
  final T? value;

  /// Returns [value] or [fallback] when the task has no decoded result.
  T valueOr(T fallback) => value ?? fallback;

  /// Returns the decoded value, throwing when it is absent.
  T requiredValue() {
    final resolved = value;
    if (resolved == null) {
      throw StateError(
        "Task '$taskId' does not have a decoded result value.",
      );
    }
    return resolved;
  }

  /// Decodes the raw persisted task payload with [codec].
  TResult? payloadAs<TResult>({required PayloadCodec<TResult> codec}) {
    final stored = rawPayload;
    if (stored == null) return null;
    return codec.decode(stored);
  }

  /// Decodes the raw persisted task payload with a JSON decoder.
  TResult? payloadJson<TResult>({
    required TResult Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    final stored = rawPayload;
    if (stored == null) return null;
    return PayloadCodec<TResult>.json(
      decode: decode,
      typeName: typeName,
    ).decode(stored);
  }

  /// Decodes the raw persisted task payload with a version-aware JSON
  /// decoder.
  TResult? payloadVersionedJson<TResult>({
    required int version,
    required TResult Function(Map<String, dynamic> payload, int version) decode,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    final stored = rawPayload;
    if (stored == null) return null;
    return PayloadCodec<TResult>.versionedJson(
      version: version,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: typeName,
    ).decode(stored);
  }

  /// Raw payload stored by the backend (useful for debugging or manual casts).
  final Object? rawPayload;

  /// Indicates the helper returned because the timeout elapsed before the task
  /// reached a terminal state.
  final bool timedOut;

  /// Whether the task completed successfully.
  bool get isSucceeded => status.state == TaskState.succeeded;

  /// Whether the task failed.
  bool get isFailed => status.state == TaskState.failed;

  /// Whether the task was cancelled.
  bool get isCancelled => status.state == TaskState.cancelled;
}
