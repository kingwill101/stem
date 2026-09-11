import 'dart:collection';
import 'dart:convert';

/// Optional typed lookup of standard payload codecs with JSON defaults.
///
/// Built-ins cover scalar JSON values, [Object], `List<Object?>`, and
/// `Map<String, Object?>`, including nullable variants. More specific
/// collection types and DTOs require explicit registration.
/// No `fromJson` is discovered. Custom codecs are format-agnostic and must
/// produce values supported by the selected transport and persistence backend.
/// Registration does not guarantee that a custom output can be persisted.
class PayloadCodecRegistry {
  /// Creates a registry with JSON scalar and untyped-tree defaults.
  PayloadCodecRegistry() : _codecs = {}, _frozen = false;

  PayloadCodecRegistry._(Map<Type, Object> codecs)
    : _codecs = Map.unmodifiable(codecs),
      _frozen = true;

  final Map<Type, Object> _codecs;
  final bool _frozen;

  static final Map<Type, Object> _defaults = _jsonDefaults();

  static Map<Type, Object> _jsonDefaults() {
    final codecs = <Type, Object>{Null: _JsonCodec<Null>()};
    _addDefault<String>(codecs);
    _addDefault<bool>(codecs);
    _addDefault<int>(codecs);
    _addDefault<double>(codecs);
    _addDefault<num>(codecs);
    _addDefault<Object>(codecs);
    _addDefault<List<Object?>>(codecs);
    _addDefault<Map<String, Object?>>(codecs);
    return Map.unmodifiable(codecs);
  }

  static void _addDefault<T extends Object>(Map<Type, Object> codecs) {
    codecs[T] = _JsonCodec<T>();
    codecs[_typeOf<T?>()] = _JsonCodec<T?>();
  }

  /// Registers [codec] for exactly [T] and, if different, `T?`.
  ///
  /// The nullable lifting preserves null without invoking [codec]. Registration
  /// takes precedence over built-in defaults. Registration is atomic and
  /// rejects duplicate explicit keys, including nullable-key collisions.
  /// Custom codecs determine their own wire format; only the built-in codecs
  /// enforce JSON compatibility.
  void register<T>(Codec<T, Object?> codec) {
    if (_frozen) throw StateError('Cannot register codecs on a snapshot.');
    final nullableType = _typeOf<T?>();
    if (_codecs.containsKey(T) || _codecs.containsKey(nullableType)) {
      throw ArgumentError(
        'A payload codec is already registered for $T '
        'or $nullableType.',
      );
    }
    _codecs[T] = codec;
    if (T != nullableType) {
      _codecs[nullableType] = _NullableCodec<T>(codec);
    }
  }

  /// Returns the codec for the exact declared type [T].
  ///
  /// Throws [StateError] for missing registrations. In particular, a JSON list
  /// is not automatically reconstructed as `List<T>`.
  Codec<T, Object?> codecFor<T>() {
    final codec = _codecs[T] ?? _defaults[T];
    if (codec == null) {
      throw StateError(
        'No payload codec registered for $T. Register a Codec<$T, Object?> '
        'with register<$T>(); typed collections also need an explicit codec.',
      );
    }
    return codec as Codec<T, Object?>;
  }

  /// Returns an immutable copy, unaffected by later registrations.
  ///
  /// Codec instances themselves are shared and should be immutable.
  PayloadCodecRegistry snapshot() => PayloadCodecRegistry._(_codecs);
}

Type _typeOf<T>() => T;

class _FunctionConverter<S, T> extends Converter<S, T> {
  const _FunctionConverter(this._convert);
  final T Function(S) _convert;

  @override
  T convert(S input) => _convert(input);
}

class _JsonCodec<T> extends Codec<T, Object?> {
  @override
  Converter<T, Object?> get encoder =>
      _FunctionConverter<T, Object?>(_checkedJson);

  @override
  Converter<Object?, T> get decoder => _FunctionConverter((value) {
    _checkedJson(value);
    if (value is T) return value;
    // JSON parsers may normalize an integral double to an integer.
    if ((T == double || T == _typeOf<double?>()) && value is num) {
      return value.toDouble() as T;
    }
    throw FormatException(
      'Expected JSON payload for $T, got '
      '${value.runtimeType}.',
    );
  });
}

class _NullableCodec<T> extends Codec<T?, Object?> {
  _NullableCodec(this._codec);
  final Codec<T, Object?> _codec;

  @override
  Converter<T?, Object?> get encoder => _FunctionConverter(
    (value) => value == null ? null : _codec.encode(value),
  );

  @override
  Converter<Object?, T?> get decoder => _FunctionConverter(
    (value) => value == null ? null : _codec.decode(value),
  );
}

Object? _checkedJson(Object? value) {
  final active = HashSet<Object>.identity();
  void visit(Object? value, String path) {
    if (value == null || value is String || value is bool || value is int) {
      return;
    }
    if (value is double && value.isFinite) return;
    if (value is List || value is Map) {
      if (!active.add(value)) {
        throw FormatException('Cyclic JSON payload at $path.');
      }
      if (value is List) {
        for (var i = 0; i < value.length; i++) {
          visit(value[i], '$path[$i]');
        }
      } else if (value is Map) {
        for (final entry in value.entries) {
          if (entry.key is! String) {
            throw FormatException(
              'JSON payload at $path must use string keys.',
            );
          }
          visit(entry.value, '$path.${entry.key}');
        }
      }
      active.remove(value);
      return;
    }
    throw FormatException(
      'Unsupported JSON payload ${value.runtimeType} at $path. '
      'Use a Codec<T, Object?> that produces finite JSON values, lists, '
      'and string-keyed maps; toJson is not invoked automatically.',
    );
  }

  visit(value, r'$');
  return value;
}
