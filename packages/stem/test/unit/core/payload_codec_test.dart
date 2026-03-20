import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('PayloadCodec.map', () {
    test('decodes typed DTO payloads from durable maps', () {
      const codec = PayloadCodec<_CodecPayload>.map(
        encode: _encodeCodecPayload,
        decode: _CodecPayload.fromJson,
        typeName: '_CodecPayload',
      );

      final decoded = codec.decode({
        'id': 'payload-1',
        'count': 3,
      });

      expect(decoded.id, 'payload-1');
      expect(decoded.count, 3);
    });

    test('normalizes generic map payloads before decoding', () {
      const codec = PayloadCodec<_CodecPayload>.map(
        encode: _encodeCodecPayload,
        decode: _CodecPayload.fromJson,
        typeName: '_CodecPayload',
      );

      final decoded = codec.decode(<Object?, Object?>{
        'id': 'payload-2',
        'count': 7,
      });

      expect(decoded.id, 'payload-2');
      expect(decoded.count, 7);
    });

    test('rejects non-map payloads with a clear error', () {
      const codec = PayloadCodec<_CodecPayload>.map(
        encode: _encodeCodecPayload,
        decode: _CodecPayload.fromJson,
        typeName: '_CodecPayload',
      );

      expect(
        () => codec.decode('not-a-map'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('_CodecPayload payload must decode to Map<String, Object?>'),
          ),
        ),
      );
    });

    test('rejects non-string map keys with a clear error', () {
      const codec = PayloadCodec<_CodecPayload>.map(
        encode: _encodeCodecPayload,
        decode: _CodecPayload.fromJson,
        typeName: '_CodecPayload',
      );

      expect(
        () => codec.decode(<Object?, Object?>{1: 'bad'}),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('_CodecPayload payload must use string keys.'),
          ),
        ),
      );
    });
  });
}

class _CodecPayload {
  const _CodecPayload({required this.id, required this.count});

  factory _CodecPayload.fromJson(Map<String, Object?> json) {
    return _CodecPayload(
      id: json['id']! as String,
      count: json['count']! as int,
    );
  }

  final String id;
  final int count;

  Map<String, Object?> toJson() => {
    'id': id,
    'count': count,
  };
}

Object? _encodeCodecPayload(_CodecPayload value) => value.toJson();
