import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('PayloadCodec.json', () {
    test('encodes and decodes DTOs via toJson/fromJson', () {
      const codec = PayloadCodec<_CodecPayload>.json(
        decode: _CodecPayload.fromJson,
        typeName: '_CodecPayload',
      );

      final payload = codec.encode(
        const _CodecPayload(id: 'payload-0', count: 1),
      );
      final decoded = codec.decode(payload);

      expect(payload, {
        'id': 'payload-0',
        'count': 1,
      });
      expect(decoded.id, 'payload-0');
      expect(decoded.count, 1);
    });

    test('accepts DTO decoders that use Map<String, dynamic>', () {
      const codec = PayloadCodec<_DynamicCodecPayload>.json(
        decode: _DynamicCodecPayload.fromJson,
        typeName: '_DynamicCodecPayload',
      );

      final payload = codec.encode(
        const _DynamicCodecPayload(id: 'payload-dyn', count: 9),
      );
      final decoded = codec.decode(payload);

      expect(payload, {
        'id': 'payload-dyn',
        'count': 9,
      });
      expect(decoded.id, 'payload-dyn');
      expect(decoded.count, 9);
    });

    test('rejects values without toJson with a clear error', () {
      const codec = PayloadCodec<_NoJsonPayload>.json(
        decode: _NoJsonPayload.fromJson,
        typeName: '_NoJsonPayload',
      );

      expect(
        () => codec.encode(const _NoJsonPayload(id: 'missing')),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('_NoJsonPayload must expose toJson()'),
          ),
        ),
      );
    });
  });

  group('PayloadCodec.versionedJson', () {
    test('encodes DTOs to versioned JSON maps without a codec instance', () {
      final payload = PayloadCodec.encodeVersionedJsonMap(
        const _VersionedCodecPayload(id: 'payload-v-encode', count: 6),
        version: 4,
        typeName: '_VersionedCodecPayload',
      );

      expect(payload, {
        PayloadCodec.versionKey: 4,
        'id': 'payload-v-encode',
        'count': 6,
      });
    });

    test('encodes DTOs with a persisted schema version', () {
      const codec = PayloadCodec<_VersionedCodecPayload>.versionedJson(
        version: 2,
        decode: _VersionedCodecPayload.fromVersionedJson,
        typeName: '_VersionedCodecPayload',
      );

      final payload = codec.encode(
        const _VersionedCodecPayload(id: 'payload-v0', count: 4),
      );

      expect(payload, {
        PayloadCodec.versionKey: 2,
        'id': 'payload-v0',
        'count': 4,
      });
    });

    test('passes the persisted schema version to the decoder', () {
      const codec = PayloadCodec<_VersionedCodecPayload>.versionedJson(
        version: 2,
        decode: _VersionedCodecPayload.fromVersionedJson,
        typeName: '_VersionedCodecPayload',
      );

      final decoded = codec.decode({
        PayloadCodec.versionKey: 3,
        'id': 'payload-v1',
        'count': 8,
      });

      expect(decoded.id, 'payload-v1');
      expect(decoded.count, 8);
      expect(decoded.decodedVersion, 3);
    });

    test('falls back to the configured default decode version', () {
      const codec = PayloadCodec<_VersionedCodecPayload>.versionedJson(
        version: 3,
        defaultDecodeVersion: 1,
        decode: _VersionedCodecPayload.fromVersionedJson,
        typeName: '_VersionedCodecPayload',
      );

      final decoded = codec.decode({
        'id': 'payload-v2',
        'count': 11,
      });

      expect(decoded.id, 'payload-v2');
      expect(decoded.count, 11);
      expect(decoded.decodedVersion, 1);
    });

    test('rejects invalid persisted schema versions with a clear error', () {
      const codec = PayloadCodec<_VersionedCodecPayload>.versionedJson(
        version: 2,
        decode: _VersionedCodecPayload.fromVersionedJson,
        typeName: '_VersionedCodecPayload',
      );

      expect(
        () => codec.decode({
          PayloadCodec.versionKey: true,
          'id': 'payload-v3',
          'count': 13,
        }),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(
              '_VersionedCodecPayload payload version must be an '
              'int-compatible '
              'value',
            ),
          ),
        ),
      );
    });
  });

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
            contains('_CodecPayload payload must decode to a string-keyed map'),
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

  factory _CodecPayload.fromJson(Map<String, dynamic> json) {
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

class _DynamicCodecPayload {
  const _DynamicCodecPayload({required this.id, required this.count});

  factory _DynamicCodecPayload.fromJson(Map<String, dynamic> json) {
    return _DynamicCodecPayload(
      id: json['id']! as String,
      count: json['count']! as int,
    );
  }

  final String id;
  final int count;

  Map<String, dynamic> toJson() => {
    'id': id,
    'count': count,
  };
}

Object? _encodeCodecPayload(_CodecPayload value) => value.toJson();

class _NoJsonPayload {
  const _NoJsonPayload({required this.id});

  factory _NoJsonPayload.fromJson(Map<String, dynamic> json) {
    return _NoJsonPayload(id: json['id']! as String);
  }

  final String id;
}

class _VersionedCodecPayload {
  const _VersionedCodecPayload({
    required this.id,
    required this.count,
    this.decodedVersion,
  });

  factory _VersionedCodecPayload.fromVersionedJson(
    Map<String, dynamic> json,
    int version,
  ) {
    return _VersionedCodecPayload(
      id: json['id']! as String,
      count: json['count']! as int,
      decodedVersion: version,
    );
  }

  final String id;
  final int count;
  final int? decodedVersion;

  Map<String, Object?> toJson() => {
    'id': id,
    'count': count,
  };
}
