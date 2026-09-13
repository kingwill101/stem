import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:workflow_host_prototype/example_binary_codec.dart';
import 'package:workflow_host_prototype/workflow_host.dart';

void main() {
  const codec = BinaryMessageCodec();

  test('documented wire bytes, empty and Unicode round trips', () {
    expect(codec.encode(const BinaryMessage('A')), [
      0x42,
      0x4d,
      1,
      0,
      0,
      0,
      1,
      65,
    ]);
    for (final text in ['', 'Ada 🌱', 'é' * 256]) {
      final bytes = codec.encoder.convert(BinaryMessage(text));
      expect(bytes, isA<Uint8List>());
      expect(codec.decode(bytes).text, text);
      final envelope = jsonDecode(jsonEncode({'value': bytes})) as Map;
      expect(envelope['value'], isNot(isA<Uint8List>()));
      expect(codec.decode(envelope['value']).text, text);
    }
  });

  test('rejects malformed framing and UTF-8', () {
    final bytes = codec.encoder.convert(const BinaryMessage('A'));
    for (var length = 0; length < bytes.length; length++) {
      expect(
        () => codec.decode(bytes.sublist(0, length)),
        throwsFormatException,
      );
    }
    for (final malformed in [
      [...bytes, 0],
      [...bytes]..[0] = 0,
      [...bytes]..[2] = 2,
      [...bytes]..[6] = 0,
      [...bytes]..[7] = 0xff,
    ]) {
      expect(() => codec.decode(malformed), throwsFormatException);
    }
  });

  test('validates JSON byte types and ranges before buffer reconstruction', () {
    for (final invalid in <Object?>[
      null,
      'bytes',
      {},
      [256],
      [-1],
      [1.0],
      ['1'],
      [null],
      [true],
    ]) {
      expect(() => codec.decode(invalid), throwsFormatException);
    }
  });

  test(
    'one registration covers workflow input, result and checkpoint replay',
    () async {
      var calls = 0;
      final workflow = HostedWorkflow<BinaryMessage, BinaryMessage>(
        name: 'binary-test',
        run: (flow, input) async {
          expect(input.text, 'Ada 🌱');
          final first = await flow.step('message', () {
            calls++;
            return BinaryMessage('Hello, ${input.text}!');
          });
          final replay = await flow.step<BinaryMessage>(
            'message',
            () => throw StateError('Must replay'),
          );
          expect(replay.text, first.text);
          expect(identical(replay, first), isFalse);
          return replay;
        },
      );
      await WorkflowHost.run<void>(
        workflows: [workflow],
        codecs: PayloadCodecRegistry()..register<BinaryMessage>(codec),
        body: (host) async {
          final result = await host.execute(
            workflow,
            const BinaryMessage('Ada 🌱'),
          );
          expect(result.text, 'Hello, Ada 🌱!');
          expect(calls, 1);
        },
      );
    },
  );

  test('binary CLI succeeds and closes the host', () async {
    final process = await Process.run(Platform.resolvedExecutable, [
      'run',
      'bin/binary_codec.dart',
    ]);
    expect(process.exitCode, 0, reason: '${process.stderr}');
    expect(process.stdout, contains('JSON reconstruction: Ada 🌱'));
    expect(process.stdout, contains('Hello, Ada 🌱!'));
  }, timeout: const Timeout(Duration(seconds: 60)));
}
