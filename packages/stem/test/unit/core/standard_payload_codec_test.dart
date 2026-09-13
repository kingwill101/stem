import 'dart:convert';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

// Deliberately has no toJson/fromJson methods or PayloadCodec dependency.
class _Message {
  const _Message(this.text);

  final String text;
}

class _MessageCodec extends Codec<_Message, Object?> {
  const _MessageCodec();

  @override
  Converter<_Message, Object?> get encoder => const _MessageEncoder();

  @override
  Converter<Object?, _Message> get decoder => const _MessageDecoder();
}

class _MessageEncoder extends Converter<_Message, Object?> {
  const _MessageEncoder();

  @override
  Object? convert(_Message input) => {'text': input.text};
}

class _MessageDecoder extends Converter<Object?, _Message> {
  const _MessageDecoder();

  @override
  _Message convert(Object? input) =>
      _Message((input! as Map)['text'] as String);
}

void main() {
  const codec = _MessageCodec();

  test('standard converters support typed task args and result transport', () {
    final definition = TaskDefinition<_Message, _Message>.codec(
      name: 'standard.message',
      argsCodec: codec,
      resultCodec: codec,
    );
    final call = definition.buildCall(const _Message('hello'));
    final resultEncoder = definition.metadata.resultEncoder!;

    expect(call.encodeArgs(), {'text': 'hello'});
    expect(resultEncoder.id, 'standard.message.result.codec');
    final payload = resultEncoder.encode(const _Message('done'));
    expect(payload, {'text': 'done'});
    expect((resultEncoder.decode(payload)! as _Message).text, 'done');
    expect(resultEncoder.encode(null), isNull);
    expect(resultEncoder.decode(null), isNull);
    expect(
      <String, Object?>{
        'message': payload,
      }.requiredValue<_Message>('message', codec: codec).text,
      'done',
    );
  });

  test('standard codecs execute typed tasks through the worker', () async {
    final definition = TaskDefinition<_Message, _Message>.codec(
      name: 'standard.message.worker',
      argsCodec: codec,
      resultCodec: codec,
    );
    final handler = FunctionTaskHandler<_Message>.inline(
      name: definition.name,
      metadata: definition.metadata,
      entrypoint: (context, args) async {
        final input = codec.decode(args);
        return _Message('${input.text} done');
      },
    );
    final app = await StemApp.inMemory(tasks: [handler]);
    addTearDown(app.shutdown);
    await app.start();
    final taskId = await app.enqueueCall(
      definition.buildCall(const _Message('task')),
    );
    final result = await app.waitForTask<_Message>(
      taskId,
      timeout: const Duration(seconds: 2),
    );
    expect(result?.value?.text, 'task done');
  });

  test('flow steps and script checkpoints preserve absent values', () {
    final step = FlowStep.typed<_Message>(
      name: 'message',
      handler: (_) async => const _Message('step'),
      valueCodec: codec,
    );
    final checkpoint = WorkflowCheckpoint.typed<_Message>(
      name: 'message',
      valueCodec: codec,
    );
    expect(step.encodeValue(const _Message('step')), {'text': 'step'});
    expect(
      (step.decodeValue({'text': 'step'})! as _Message).text,
      'step',
    );
    expect(checkpoint.encodeValue(const _Message('step')), {'text': 'step'});
    expect(
      (checkpoint.decodeValue({'text': 'step'})! as _Message).text,
      'step',
    );
    expect(step.encodeValue(null), isNull);
    expect(step.decodeValue(null), isNull);
    expect(checkpoint.encodeValue(null), isNull);
    expect(checkpoint.decodeValue(null), isNull);
  });

  test(
    'standard codecs persist workflow params, checkpoints and results',
    () async {
      final flow = Flow<_Message>.codec(
        name: 'standard.message.flow',
        resultCodec: codec,
        build: (builder) {
          builder
            ..step<_Message>(
              'input',
              (context) async => context.paramsAs(codec: codec),
              valueCodec: codec,
            )
            ..step<_Message>(
              'finish',
              (context) async {
                final previous = context.requiredPreviousValue(codec: codec);
                return _Message('${previous.text} done');
              },
              valueCodec: codec,
            );
        },
      );
      final script = WorkflowScript<_Message>.codec(
        name: 'standard.message.script',
        resultCodec: codec,
        checkpoints: [
          WorkflowCheckpoint.typed<_Message>(
            name: 'message',
            valueCodec: codec,
          ),
        ],
        run: (context) => context.step<_Message>(
          'message',
          (_) async => context.paramsAs(codec: codec),
        ),
      );
      final app = await StemWorkflowApp.inMemory(
        flows: [flow],
        scripts: [script],
      );
      addTearDown(app.shutdown);
      await app.start();
      final ref = flow.refCodec(paramsCodec: codec);
      final runId = await ref.start(app, params: const _Message('hello'));
      final result = await ref.waitFor(
        app,
        runId,
        timeout: const Duration(seconds: 2),
      );

      expect(result?.value?.text, 'hello done');
      expect(result?.state.params, containsPair('text', 'hello'));
      expect(result?.state.result, {'text': 'hello done'});
      expect(
        await app.store.readStep<Map<String, Object?>>(runId, 'input'),
        {'text': 'hello'},
      );
      final scriptRef = script.refCodec(paramsCodec: codec);
      final scriptResult = await scriptRef.startAndWait(
        app,
        params: const _Message('script'),
        timeout: const Duration(seconds: 2),
      );
      expect(scriptResult?.value?.text, 'script');
      expect(scriptResult?.state.result, {'text': 'script'});
    },
  );

  test('standard event codecs resume waiting workflows', () async {
    final event = WorkflowEventRef<_Message>.codec(
      topic: 'standard.message.event',
      codec: codec,
    );
    final flow = Flow<String>(
      name: 'standard.message.wait',
      build: (builder) {
        builder.step('wait', (context) async {
          final message = event.waitValue(context);
          return message?.text;
        });
      },
    );
    final app = await StemWorkflowApp.inMemory(flows: [flow]);
    addTearDown(app.shutdown);
    // Drive execution explicitly; a live worker would race these calls.
    final ref = flow.ref0();
    final runId = await ref.start(app);
    await app.executeRun(runId);
    await event.emit(app, const _Message('resumed'));
    await app.executeRun(runId);
    final result = await ref.waitFor(
      app,
      runId,
      timeout: const Duration(seconds: 2),
    );
    expect(result?.value, 'resumed');
  });

  test(
    'PayloadCodec retains callbacks with standard converter composition',
    () {
      final Codec<_Message, Object?> payloadCodec = PayloadCodec<_Message>(
        encode: (value) => {'text': value.text},
        decode: (value) => _Message((value! as Map)['text'] as String),
      );
      final jsonCodec = payloadCodec.fuse(json);
      expect(jsonCodec.encode(const _Message('fused')), '{"text":"fused"}');
      expect(jsonCodec.decode('{"text":"decoded"}').text, 'decoded');
      expect(
        payloadCodec.decoder
            .convert(
              payloadCodec.encoder.convert(
                const _Message('converter'),
              ),
            )
            .text,
        'converter',
      );
      expect(
        payloadCodec.inverted.encode({'text': 'inverse'}).text,
        'inverse',
      );
    },
  );

  test(
    'versioned map converter retains schema evolution and normalization',
    () {
      final Codec<_Message, Object?> versioned =
          PayloadCodec<_Message>.versionedMap(
            version: 2,
            defaultDecodeVersion: 1,
            encode: (value) => {'text': value.text},
            decode: (payload, version) {
              expect(payload, isNot(contains(PayloadCodec.versionKey)));
              return _Message(
                (version == 1 ? payload['legacy'] : payload['text'])! as String,
              );
            },
          );
      expect(versioned.encoder.convert(const _Message('current')), {
        PayloadCodec.versionKey: 2,
        'text': 'current',
      });
      expect(versioned.decoder.convert({'legacy': 'old'}).text, 'old');
      expect(
        versioned
            .fuse(json)
            .decode(
              '{"__stemPayloadVersion":2,"text":"new"}',
            )
            .text,
        'new',
      );
    },
  );
}
