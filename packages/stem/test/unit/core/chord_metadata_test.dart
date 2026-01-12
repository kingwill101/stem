import 'package:stem/src/core/chord_metadata.dart';
import 'package:test/test.dart';

void main() {
  test('ChordMetadata exposes expected keys', () {
    expect(
      ChordMetadata.callbackEnvelope,
      equals('stem.chord.callbackEnvelope'),
    );
    expect(ChordMetadata.dispatchedAt, equals('stem.chord.dispatchedAt'));
    expect(ChordMetadata.callbackTaskId, equals('stem.chord.callbackTaskId'));
  });
}
