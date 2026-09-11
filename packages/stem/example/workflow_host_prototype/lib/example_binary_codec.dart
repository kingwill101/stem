import 'dart:convert';
import 'dart:typed_data';

/// The single-field DTO used by the custom binary example.
class BinaryMessage {
  const BinaryMessage(this.text);

  final String text;
}

/// Example-only binary format (not protobuf or CBOR).
///
/// Bytes 0–1 are ASCII `BM`, byte 2 is version 1, bytes 3–6 are an
/// unsigned big-endian UTF-8 byte length, and the remaining bytes are UTF-8.
/// The decoder accepts either a [Uint8List] or a JSON-decoded list of bytes.
/// This adaptation does not imply that a backend transports raw binary.
class BinaryMessageCodec extends Codec<BinaryMessage, Object?> {
  const BinaryMessageCodec();

  @override
  Converter<BinaryMessage, Uint8List> get encoder => const _MessageEncoder();

  @override
  Converter<Object?, BinaryMessage> get decoder => const _MessageDecoder();
}

class _MessageEncoder extends Converter<BinaryMessage, Uint8List> {
  const _MessageEncoder();

  @override
  Uint8List convert(BinaryMessage input) {
    final content = utf8.encode(input.text);
    if (content.length > 0xffffffff) {
      throw const FormatException(
        'BinaryMessage content exceeds uint32 length',
      );
    }
    final bytes = Uint8List(7 + content.length);
    bytes.setRange(0, 3, [0x42, 0x4d, 1]);
    ByteData.sublistView(bytes).setUint32(3, content.length, Endian.big);
    bytes.setRange(7, bytes.length, content);
    return bytes;
  }
}

class _MessageDecoder extends Converter<Object?, BinaryMessage> {
  const _MessageDecoder();

  @override
  BinaryMessage convert(Object? input) {
    final Uint8List bytes;
    if (input is Uint8List) {
      bytes = input;
    } else if (input is List) {
      // Uint8List.fromList alone silently truncates out-of-range integers.
      final values = <int>[];
      for (final value in input) {
        if (value is! int || value < 0 || value > 255) {
          throw const FormatException('Expected integer bytes in range 0–255');
        }
        values.add(value);
      }
      bytes = Uint8List.fromList(values);
    } else {
      throw const FormatException('Expected Uint8List or JSON byte list');
    }
    if (bytes.length < 7) {
      throw const FormatException('Truncated BinaryMessage header');
    }
    if (bytes[0] != 0x42 || bytes[1] != 0x4d) {
      throw const FormatException('Invalid BinaryMessage magic');
    }
    if (bytes[2] != 1) {
      throw const FormatException('Unsupported BinaryMessage version');
    }
    final length = ByteData.sublistView(bytes).getUint32(3, Endian.big);
    if (bytes.length - 7 != length) {
      throw const FormatException('Truncated content or trailing bytes');
    }
    return BinaryMessage(utf8.decode(Uint8List.sublistView(bytes, 7)));
  }
}
