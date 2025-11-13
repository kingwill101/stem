/// Transforms task handler results to and from backend-friendly payloads.
///
/// Implementations can encrypt, compress, or otherwise mutate payloads before
/// persistence. They MUST ensure every invocation of [encode] is reversible via
/// [decode].
///
/// Example usage:
/// ```dart
/// final encoder = JsonTaskPayloadEncoder();
/// final encoded = encoder.encode({'key': 'value'});
/// final decoded = encoder.decode(encoded);
/// print(decoded); // {'key': 'value'}
/// ```
abstract class TaskPayloadEncoder {
  const TaskPayloadEncoder();

  /// Globally unique identifier so other processes can resolve the encoder
  /// when decoding payloads.
  ///
  /// Example:
  /// ```dart
  /// final encoder = JsonTaskPayloadEncoder();
  /// print(encoder.id); // 'json'
  /// ```
  String get id => runtimeType.toString();

  /// Converts the handler's return value into a backend-friendly object.
  ///
  /// The returned value MUST be JSON-serializable when using JSON-based
  /// backends. Encoders targeting binary-friendly stores can return `Uint8List`
  /// or other objects supported by the backend.
  ///
  /// Example:
  /// ```dart
  /// final encoder = JsonTaskPayloadEncoder();
  /// final encoded = encoder.encode({'key': 'value'});
  /// print(encoded); // {'key': 'value'}
  /// ```
  Object? encode(Object? value);

  /// Reconstructs the original handler value from the stored payload.
  ///
  /// Example:
  /// ```dart
  /// final encoder = JsonTaskPayloadEncoder();
  /// final decoded = encoder.decode({'key': 'value'});
  /// print(decoded); // {'key': 'value'}
  /// ```
  Object? decode(Object? stored);
}

/// Default encoder that stores payloads verbatim as JSON-friendly values.
///
/// Example usage:
/// ```dart
/// final encoder = JsonTaskPayloadEncoder();
/// final encoded = encoder.encode({'key': 'value'});
/// final decoded = encoder.decode(encoded);
/// print(decoded); // {'key': 'value'}
/// ```
class JsonTaskPayloadEncoder extends TaskPayloadEncoder {
  const JsonTaskPayloadEncoder();

  @override
  String get id => 'json';

  @override
  Object? encode(Object? value) => value;

  @override
  Object? decode(Object? stored) => stored;
}

/// Registry for managing and resolving [TaskPayloadEncoder] instances.
///
/// This class allows you to register encoders and resolve them by their unique
/// [id]. It also provides default encoders for handling task results and
/// arguments.
///
/// Example usage:
/// ```dart
/// final registry = TaskPayloadEncoderRegistry(
///   defaultResultEncoder: JsonTaskPayloadEncoder(),
///   defaultArgsEncoder: JsonTaskPayloadEncoder(),
/// );
///
/// registry.register(MyCustomEncoder());
///
/// final encoder = registry.resolveResult('json');
/// print(encoder.id); // 'json'
/// ```
class TaskPayloadEncoderRegistry {
  TaskPayloadEncoderRegistry({
    required this.defaultResultEncoder,
    required this.defaultArgsEncoder,
    Iterable<TaskPayloadEncoder> additionalEncoders = const [],
  }) {
    _register(defaultResultEncoder);
    if (defaultArgsEncoder.id != defaultResultEncoder.id) {
      _register(defaultArgsEncoder);
    }
    for (final encoder in additionalEncoders) {
      _register(encoder);
    }
  }

  /// The default encoder for task results.
  final TaskPayloadEncoder defaultResultEncoder;

  /// The default encoder for task arguments.
  final TaskPayloadEncoder defaultArgsEncoder;

  final Map<String, TaskPayloadEncoder> _encoders = {};

  /// Registers a new [TaskPayloadEncoder] in the registry.
  ///
  /// If an encoder with the same [id] already exists, it will be replaced.
  ///
  /// Example:
  /// ```dart
  /// final registry = TaskPayloadEncoderRegistry(
  ///   defaultResultEncoder: JsonTaskPayloadEncoder(),
  ///   defaultArgsEncoder: JsonTaskPayloadEncoder(),
  /// );
  /// registry.register(MyCustomEncoder());
  /// ```
  void register(TaskPayloadEncoder? encoder) {
    if (encoder == null) return;
    _register(encoder);
  }

  /// Resolves the encoder for task results by its [id].
  ///
  /// If no encoder is found for the given [id], the [defaultResultEncoder] is
  /// returned.
  ///
  /// Example:
  /// ```dart
  /// final encoder = registry.resolveResult('json');
  /// print(encoder.id); // 'json'
  /// ```
  TaskPayloadEncoder resolveResult(String? id) {
    if (id == null) return defaultResultEncoder;
    return _encoders[id] ?? defaultResultEncoder;
  }

  /// Resolves the encoder for task arguments by its [id].
  ///
  /// If no encoder is found for the given [id], the [defaultArgsEncoder] is
  /// returned.
  ///
  /// Example:
  /// ```dart
  /// final encoder = registry.resolveArgs('custom');
  /// print(encoder.id); // 'custom'
  /// ```
  TaskPayloadEncoder resolveArgs(String? id) {
    if (id == null) return defaultArgsEncoder;
    return _encoders[id] ?? defaultArgsEncoder;
  }

  /// Returns all registered encoders.
  Iterable<TaskPayloadEncoder> get allEncoders => _encoders.values;

  void _register(TaskPayloadEncoder encoder) {
    _encoders[encoder.id] = encoder;
  }
}

/// Ensures a [TaskPayloadEncoderRegistry] is available, instantiating one when
/// [registry] is null and registering any [additionalEncoders] with whichever
/// registry is ultimately used.
///
/// Example usage:
/// ```dart
/// final registry = ensureTaskPayloadEncoderRegistry(
///   null,
///   resultEncoder: JsonTaskPayloadEncoder(),
///   argsEncoder: JsonTaskPayloadEncoder(),
///   additionalEncoders: [MyCustomEncoder()],
/// );
/// ```
TaskPayloadEncoderRegistry ensureTaskPayloadEncoderRegistry(
  TaskPayloadEncoderRegistry? registry, {
  TaskPayloadEncoder resultEncoder = const JsonTaskPayloadEncoder(),
  TaskPayloadEncoder argsEncoder = const JsonTaskPayloadEncoder(),
  Iterable<TaskPayloadEncoder> additionalEncoders = const [],
}) {
  final resolved =
      registry ??
      TaskPayloadEncoderRegistry(
        defaultResultEncoder: resultEncoder,
        defaultArgsEncoder: argsEncoder,
        additionalEncoders: additionalEncoders,
      );
  if (registry != null) {
    for (final encoder in additionalEncoders) {
      resolved.register(encoder);
    }
  }
  return resolved;
}
