/// Transforms task handler results to and from backend-friendly payloads.
///
/// Implementations can encrypt, compress, or otherwise mutate payloads before
/// persistence. They MUST ensure every invocation of [encode] is reversible via
/// [decode].
abstract class TaskResultEncoder {
  const TaskResultEncoder();

  /// Converts the handler's return value into a backend-friendly object.
  ///
  /// The returned value MUST be JSON-serializable when using JSON-based
  /// backends. Encoders targeting binary-friendly stores can return `Uint8List`
  /// or other objects supported by the backend.
  Object? encode(Object? value);

  /// Reconstructs the original handler value from the stored payload.
  Object? decode(Object? stored);
}

/// Default encoder that stores payloads verbatim as JSON-friendly values.
class JsonTaskResultEncoder extends TaskResultEncoder {
  const JsonTaskResultEncoder();

  @override
  Object? encode(Object? value) => value;

  @override
  Object? decode(Object? stored) => stored;
}
