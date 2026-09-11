import 'dart:convert';
import 'dart:typed_data';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

class _Value {
  _Value(this.number);
  final int number;

  Map<String, Object?> toJson() =>
      throw StateError('Implicit toJson must not be invoked.');
}

class _ValueEncoder extends Converter<_Value, Object?> {
  @override
  Object? convert(_Value input) => {'number': input.number};
}

class _ValueDecoder extends Converter<Object?, _Value> {
  @override
  _Value convert(Object? input) =>
      _Value((input! as Map<String, dynamic>)['number'] as int);
}

class _ValueCodec extends Codec<_Value, Object?> {
  @override
  Converter<_Value, Object?> get encoder => _ValueEncoder();
  @override
  Converter<Object?, _Value> get decoder => _ValueDecoder();
}

class _BytesEncoder extends Converter<_Value, Object?> {
  @override
  Object? convert(_Value input) => Uint8List.fromList([input.number]);
}

class _BytesDecoder extends Converter<Object?, _Value> {
  @override
  _Value convert(Object? input) {
    final bytes = Uint8List.fromList((input! as List).cast<int>());
    return _Value(bytes.single);
  }
}

class _BytesCodec extends Codec<_Value, Object?> {
  @override
  Converter<_Value, Object?> get encoder => _BytesEncoder();
  @override
  Converter<Object?, _Value> get decoder => _BytesDecoder();
}

class _BufferEncoder extends Converter<_Value, Object?> {
  @override
  Object? convert(_Value input) => ByteData(1)..setUint8(0, input.number);
}

class _BufferDecoder extends Converter<Object?, _Value> {
  @override
  _Value convert(Object? input) => _Value((input! as ByteData).getUint8(0));
}

class _BufferCodec extends Codec<_Value, Object?> {
  @override
  Converter<_Value, Object?> get encoder => _BufferEncoder();
  @override
  Converter<Object?, _Value> get decoder => _BufferDecoder();
}

class _ValuesEncoder extends Converter<List<_Value>, Object?> {
  @override
  Object? convert(List<_Value> input) =>
      input.map(_ValueCodec().encode).toList();
}

class _ValuesDecoder extends Converter<Object?, List<_Value>> {
  @override
  List<_Value> convert(Object? input) =>
      (input! as List<Object?>).map(_ValueCodec().decode).toList();
}

class _ValuesCodec extends Codec<List<_Value>, Object?> {
  @override
  Converter<List<_Value>, Object?> get encoder => _ValuesEncoder();
  @override
  Converter<Object?, List<_Value>> get decoder => _ValuesDecoder();
}

void main() {
  late PayloadCodecRegistry registry;
  setUp(() => registry = PayloadCodecRegistry());

  T roundtrip<T>(T value) {
    final codec = registry.codecFor<T>();
    return codec.decode(jsonDecode(jsonEncode(codec.encode(value))));
  }

  test('built-ins survive an actual JSON boundary', () {
    expect(roundtrip<String>('hello'), 'hello');
    expect(roundtrip<int>(42), 42);
    expect(roundtrip<double>(42), 42.0);
    expect(registry.codecFor<double>().decode(42), 42.0);
    expect(roundtrip<num>(4.5), 4.5);
    expect(roundtrip<bool>(true), isTrue);
    expect(roundtrip<Null>(null), isNull);
    expect(roundtrip<String?>(null), isNull);
    expect(roundtrip<List<Object?>>([1, 'two', null]), [1, 'two', null]);
    expect(
      roundtrip<Map<String, Object?>>({
        'list': [true],
      }),
      {
        'list': [true],
      },
    );
    expect(roundtrip<Object?>({'value': null}), {'value': null});
    expect(() => registry.codecFor<int>().decode('42'), throwsFormatException);
  });

  test('custom DTO codecs lift nullability and roundtrip JSON objects', () {
    registry.register<_Value>(_ValueCodec());
    expect(roundtrip<_Value>(_Value(42)).number, 42);
    expect(roundtrip<_Value?>(_Value(7))!.number, 7);
    expect(roundtrip<_Value?>(null), isNull);
    expect(registry.codecFor<_Value>().encode(_Value(3)), {'number': 3});
    final textCodec = registry.codecFor<_Value>().fuse(json);
    expect(textCodec.encode(_Value(3)), '{"number":3}');
    expect(textCodec.decode('{"number":3}').number, 3);
  });

  test('explicit collection codecs reconstruct typed elements', () {
    registry.register<List<_Value>>(_ValuesCodec());
    final values = roundtrip<List<_Value>>([_Value(1), _Value(2)]);
    expect(values.map((value) => value.number), [1, 2]);
    expect(roundtrip<List<_Value>?>(null), isNull);
  });

  test(
    'missing codecs and typed collections fail with registration guidance',
    () {
      for (final lookup in [
        () => registry.codecFor<_Value>(),
        () => registry.codecFor<List<String>>(),
        () => registry.codecFor<List<_Value>>(),
        () => registry.codecFor<Map<String, int>>(),
      ]) {
        expect(
          lookup,
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('Register a Codec'),
            ),
          ),
        );
      }
    },
  );

  test('invalid JSON trees never invoke implicit toJson', () {
    final codec = registry.codecFor<Object?>();
    final cycle = <Object?>[];
    cycle.add(cycle);
    for (final value in [
      double.nan,
      double.infinity,
      {'nested': _Value(1)},
      {1: 'bad key'},
      cycle,
    ]) {
      expect(() => codec.encode(value), throwsFormatException);
      expect(() => codec.decode(value), throwsFormatException);
    }
  });

  test('custom format codecs own their representation and reconstruction', () {
    registry.register<_Value>(_BytesCodec());
    final codec = registry.codecFor<_Value>();
    final bytes = codec.encode(_Value(42));
    expect(bytes, isA<Uint8List>());
    expect(codec.decode(bytes).number, 42);
    // JSON preserves byte values, not Uint8List runtime identity.
    final stored = jsonDecode(jsonEncode(bytes));
    expect(stored, isNot(isA<Uint8List>()));
    expect(codec.decode(stored).number, 42);
    expect(registry.codecFor<_Value?>().encode(null), isNull);
  });

  test(
    'custom codecs may use non-JSON formats, without transport guarantees',
    () {
      registry.register<_Value>(_BufferCodec());
      final codec = registry.codecFor<_Value>();
      final encoded = codec.encode(_Value(42));
      expect(encoded, isA<ByteData>());
      expect(codec.decode(encoded).number, 42);
      final nullable = registry.codecFor<_Value?>();
      expect(nullable.decode(nullable.encode(_Value(7)))!.number, 7);
      expect(
        () => jsonEncode(encoded),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
    },
  );

  test('duplicate and nullable-key collisions are atomic', () {
    registry.register<_Value>(_ValueCodec());
    expect(() => registry.register<_Value>(_ValueCodec()), throwsArgumentError);
    expect(
      () => registry.register<_Value?>(registry.codecFor<_Value?>()),
      throwsArgumentError,
    );
    final other = PayloadCodecRegistry()
      ..register<_Value?>(registry.codecFor<_Value?>());
    expect(() => other.register<_Value>(_ValueCodec()), throwsArgumentError);
    expect(() => other.codecFor<_Value>(), throwsStateError);
    registry.register<String>(registry.codecFor<String>());
    expect(
      () => registry.register<String>(registry.codecFor<String>()),
      throwsArgumentError,
    );
  });

  test('snapshot is immutable and independent from later registrations', () {
    final frozen = registry.snapshot();
    registry.register<_Value>(_ValueCodec());
    expect(() => frozen.codecFor<_Value>(), throwsStateError);
    expect(() => frozen.register<_Value>(_ValueCodec()), throwsStateError);
  });
}
