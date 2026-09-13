import 'dart:convert';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

// The erased representation intentionally differs from the typed codec.
// Existing subclasses can also accept values outside T at erased boundaries.
class _LegacyCodec extends PayloadCodec<String?> {
  const _LegacyCodec() : super(encode: _encodeTyped, decode: _decodeTyped);

  static Object? _encodeTyped(String? value) => {'typed': value};
  static String? _decodeTyped(Object? value) =>
      (value! as Map)['typed'] as String?;

  @override
  Object? encodeDynamic(Object? value) => {'legacy': value ?? 'null override'};

  @override
  Object? decodeDynamic(Object? payload) =>
      payload == null ? 'null override' : (payload as Map)['legacy'].toString();
}

void main() {
  const Codec<String?, Object?> codec = _LegacyCodec();

  test('task adapter honors erased representations and null overrides', () {
    const adapter = CodecTaskPayloadEncoder<String?>(
      idValue: 'legacy',
      codec: codec,
    );
    expect(adapter.encode('value'), {'legacy': 'value'});
    expect(adapter.decode({'legacy': 'value'}), 'value');
    // Must dispatch before the standard adapter's typed cast.
    expect(adapter.encode(42), {'legacy': 42});
    expect(adapter.encode(null), {'legacy': 'null override'});
    expect(adapter.decode(null), 'null override');
  });

  test('ordinary typed calls and composition do not use erased overrides', () {
    expect(codec.encode('value'), {'typed': 'value'});
    expect(codec.decode({'typed': 'value'}), 'value');
    expect(codec.encode(null), {'typed': null});
    expect(codec.fuse(json).encode('value'), '{"typed":"value"}');
    expect(codec.fuse(json).decode('{"typed":"value"}'), 'value');
  });

  test('standard-only composed codec keeps null guards and typed cast', () {
    final adapter = CodecTaskPayloadEncoder<String?>(
      idValue: 'composed',
      codec: codec.fuse(json),
    );
    expect(adapter.encode('value'), '{"typed":"value"}');
    expect(adapter.decode('{"typed":"value"}'), 'value');
    expect(adapter.encode(null), isNull);
    expect(adapter.decode(null), isNull);
    expect(() => adapter.encode(42), throwsA(isA<TypeError>()));
  });

  test(
    'step, checkpoint, and result adapters dispatch nonnull overrides '
    'while retaining outer null guards',
    () {
      final step = FlowStep.typed<String?>(
        name: 'step',
        handler: (_) async => 'value',
        valueCodec: codec,
      );
      final checkpoint = WorkflowCheckpoint.typed<String?>(
        name: 'checkpoint',
        valueCodec: codec,
      );
      final flow = WorkflowDefinition<String?>.flow(
        name: 'flow',
        build: (_) {},
        resultCodec: codec,
      );
      final script = WorkflowDefinition<String?>.script(
        name: 'script',
        run: (_) async => 'value',
        resultCodec: codec,
      );
      for (final encode in [
        step.encodeValue,
        checkpoint.encodeValue,
        flow.encodeResult,
        script.encodeResult,
      ]) {
        expect(encode('value'), {'legacy': 'value'});
        expect(encode(42), {'legacy': 42});
        // These outer APIs have always guarded absent values.
        expect(encode(null), isNull);
      }
      for (final decode in [
        step.decodeValue,
        checkpoint.decodeValue,
        flow.decodeResult,
        script.decodeResult,
      ]) {
        expect(decode({'legacy': 'value'}), 'value');
        expect(decode(null), isNull);
      }
    },
  );

  test('previous and resume values retain legacy erased decode dispatch', () {
    final context = FlowContext(
      workflow: 'flow',
      runId: 'run',
      stepName: 'step',
      params: const {},
      previousResult: const {'legacy': 'previous'},
      resumeData: const {'legacy': 'resume'},
      stepIndex: 1,
    );
    expect(context.previousValue(codec: codec), 'previous');
    expect(context.takeResumeValue(codec: codec), 'resume');
    expect(context.takeResumeValue(codec: codec), isNull);
  });

  for (final value in <String?>['event', null]) {
    test('runtime event dispatch honors legacy override for $value', () async {
      final flow = Flow<String?>.codec(
        name: 'legacy.event',
        resultCodec: codec,
        build: (builder) {
          builder.step<String?>('wait', (context) async {
            final resumed = context.takeResumeValue(codec: codec);
            if (resumed == null) {
              context.awaitEvent('legacy.ready');
              return null;
            }
            return resumed;
          }, valueCodec: codec);
        },
      );
      final app = await StemWorkflowApp.inMemory(flows: [flow]);
      addTearDown(app.shutdown);
      final ref = flow.ref0();
      final runId = await ref.start(app);
      await app.executeRun(runId);
      await app.runtime.emitValue('legacy.ready', value, codec: codec);
      await app.executeRun(runId);
      final result = await ref.waitFor(
        app,
        runId,
        timeout: const Duration(seconds: 2),
      );
      final expected = value ?? 'null override';
      expect(result?.value, expected);
      expect(result?.state.result, {'legacy': expected});
      expect(
        await app.store.readStep<Map<String, Object?>>(runId, 'wait'),
        {'legacy': expected},
      );
    });
  }
}
