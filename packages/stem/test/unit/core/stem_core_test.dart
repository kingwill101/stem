import 'dart:async';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('Envelope', () {
    test('round trips through json', () {
      final envelope = Envelope(
        id: 'abc',
        name: 'example',
        args: {'value': 42},
        headers: {'trace-id': '123'},
        notBefore: DateTime.utc(2024, 01, 02, 03, 04, 05),
        priority: 3,
        attempt: 2,
        maxRetries: 5,
        visibilityTimeout: const Duration(seconds: 30),
        queue: 'emails',
        meta: {'foo': 'bar'},
      );

      final json = envelope.toJson();
      final copy = Envelope.fromJson(json);

      expect(copy.id, equals(envelope.id));
      expect(copy.name, equals(envelope.name));
      expect(copy.args, equals({'value': 42}));
      expect(copy.headers, equals({'trace-id': '123'}));
      expect(copy.notBefore, equals(envelope.notBefore));
      expect(copy.priority, equals(3));
      expect(copy.attempt, equals(2));
      expect(copy.maxRetries, equals(5));
      expect(copy.visibilityTimeout, equals(const Duration(seconds: 30)));
      expect(copy.queue, equals('emails'));
      expect(copy.meta, equals({'foo': 'bar'}));
    });

    test('decodes whole args and meta DTO payloads', () {
      final envelope = Envelope(
        name: 'example',
        args: const {
          PayloadCodec.versionKey: 2,
          'value': 42,
        },
        meta: const {
          PayloadCodec.versionKey: 2,
          'label': 'queued',
        },
      );

      expect(
        envelope.argsJson<_EnvelopeArgs>(decode: _EnvelopeArgs.fromJson).value,
        42,
      );
      expect(
        envelope
            .argsVersionedJson<_EnvelopeArgs>(
              version: 2,
              decode: _EnvelopeArgs.fromVersionedJson,
            )
            .value,
        42,
      );
      expect(
        envelope.metaJson<_EnvelopeMeta>(decode: _EnvelopeMeta.fromJson).label,
        'queued',
      );
      expect(
        envelope
            .metaVersionedJson<_EnvelopeMeta>(
              version: 2,
              decode: _EnvelopeMeta.fromVersionedJson,
            )
            .label,
        'queued',
      );
    });
  });

  group('StemConfig', () {
    test('reads from environment with defaults', () {
      final config = StemConfig.fromEnvironment({
        'STEM_BROKER_URL': 'redis://localhost:6379',
        'STEM_DEFAULT_MAX_RETRIES': '7',
      });

      expect(config.brokerUrl, equals('redis://localhost:6379'));
      expect(config.defaultQueue, equals('default'));
      expect(config.defaultMaxRetries, equals(7));
      expect(config.prefetchMultiplier, equals(2));
      expect(config.resultBackendUrl, isNull);
    });

    test('throws when broker url missing', () {
      expect(() => StemConfig.fromEnvironment({}), throwsStateError);
    });
  });

  group('Stem.enqueue', () {
    test('publishes to broker and writes queued state', () async {
      final broker = _RecordingBroker();
      final backend = _RecordingBackend();
      final stem = Stem(
        broker: broker,
        backend: backend,
        tasks: [const _StubTaskHandler()],
      );

      final id = await stem.enqueue(
        'sample.task',
        args: {'value': 'ok'},
        options: const TaskOptions(queue: 'custom', maxRetries: 4),
      );

      expect(broker.published.single.envelope.id, equals(id));
      expect(broker.published.single.envelope.queue, equals('custom'));
      expect(backend.records.single.id, equals(id));
      expect(backend.records.single.state, equals(TaskState.queued));
    });

    test(
      'enqueueCall publishes typed calls without requiring registry handlers',
      () async {
        final broker = _RecordingBroker();
        final backend = _RecordingBackend();
        final stem = Stem(broker: broker, backend: backend);
        final definition = TaskDefinition<({String value}), Object?>(
          name: 'sample.typed',
          encodeArgs: (args) => {'value': args.value},
          defaultOptions: const TaskOptions(queue: 'typed'),
        );

        final id = await stem.enqueueCall(definition.buildCall((value: 'ok')));

        expect(id, isNotEmpty);
        expect(broker.published.single.envelope.name, 'sample.typed');
        expect(broker.published.single.envelope.queue, 'typed');
        expect(backend.records.single.id, id);
        expect(backend.records.single.state, TaskState.queued);
      },
    );

    test('enqueueCall publishes codec-backed task definitions', () async {
      final broker = _RecordingBroker();
      final backend = _RecordingBackend();
      final stem = Stem(broker: broker, backend: backend);
      final definition = TaskDefinition<_CodecTaskArgs, Object?>.codec(
        name: 'sample.codec.args',
        argsCodec: _codecTaskArgsCodec,
        defaultOptions: const TaskOptions(queue: 'typed'),
      );

      final id = await stem.enqueueCall(
        definition.buildCall(const _CodecTaskArgs('encoded')),
      );

      expect(id, isNotEmpty);
      expect(broker.published.single.envelope.name, 'sample.codec.args');
      expect(broker.published.single.envelope.queue, 'typed');
      expect(broker.published.single.envelope.args, {'value': 'encoded'});
      expect(backend.records.single.id, id);
      expect(backend.records.single.state, TaskState.queued);
    });

    test('enqueueCall publishes json-backed task definitions', () async {
      final broker = _RecordingBroker();
      final backend = _RecordingBackend();
      final stem = Stem(broker: broker, backend: backend);
      final definition = TaskDefinition<_CodecTaskArgs, Object?>.json(
        name: 'sample.json.args',
        defaultOptions: const TaskOptions(queue: 'typed'),
      );

      final id = await stem.enqueueCall(
        definition.buildCall(const _CodecTaskArgs('encoded')),
      );

      expect(id, isNotEmpty);
      expect(broker.published.single.envelope.name, 'sample.json.args');
      expect(broker.published.single.envelope.queue, 'typed');
      expect(broker.published.single.envelope.args, {'value': 'encoded'});
      expect(backend.records.single.id, id);
      expect(backend.records.single.state, TaskState.queued);
    });

    test('enqueueCall publishes versioned-json task definitions', () async {
      final broker = _RecordingBroker();
      final backend = _RecordingBackend();
      final stem = Stem(broker: broker, backend: backend);
      final definition = TaskDefinition<_CodecTaskArgs, Object?>.versionedJson(
        name: 'sample.versioned.json.args',
        version: 2,
        defaultOptions: const TaskOptions(queue: 'typed'),
      );

      final id = await stem.enqueueCall(
        definition.buildCall(const _CodecTaskArgs('encoded')),
      );

      expect(id, isNotEmpty);
      expect(
        broker.published.single.envelope.name,
        'sample.versioned.json.args',
      );
      expect(broker.published.single.envelope.queue, 'typed');
      expect(broker.published.single.envelope.args, {
        PayloadCodec.versionKey: 2,
        'value': 'encoded',
      });
      expect(backend.records.single.id, id);
      expect(backend.records.single.state, TaskState.queued);
    });

    test('enqueueCall publishes versioned-map task definitions', () async {
      final broker = _RecordingBroker();
      final backend = _RecordingBackend();
      final stem = Stem(broker: broker, backend: backend);
      final definition = TaskDefinition<_CodecTaskArgs, Object?>.versionedMap(
        name: 'sample.versioned.map.args',
        version: 3,
        encodeArgs: (args) => {'legacy_value': args.value},
        defaultOptions: const TaskOptions(queue: 'typed'),
      );

      final id = await stem.enqueueCall(
        definition.buildCall(const _CodecTaskArgs('encoded')),
      );

      expect(id, isNotEmpty);
      expect(
        broker.published.single.envelope.name,
        'sample.versioned.map.args',
      );
      expect(broker.published.single.envelope.queue, 'typed');
      expect(broker.published.single.envelope.args, {
        PayloadCodec.versionKey: 3,
        'legacy_value': 'encoded',
      });
      expect(backend.records.single.id, id);
      expect(backend.records.single.state, TaskState.queued);
    });

    test('enqueueJson publishes DTO args without a manual map', () async {
      final broker = _RecordingBroker();
      final backend = _RecordingBackend();
      final stem = Stem(
        broker: broker,
        backend: backend,
        tasks: [const _StubTaskHandler()],
      );

      final id = await stem.enqueueJson(
        'sample.task',
        const _CodecTaskArgs('encoded'),
      );

      expect(id, isNotEmpty);
      expect(broker.published.single.envelope.args, {'value': 'encoded'});
      expect(backend.records.single.id, id);
      expect(backend.records.single.state, TaskState.queued);
    });

    test(
      'enqueueVersionedJson publishes DTO args with a persisted schema version',
      () async {
        final broker = _RecordingBroker();
        final backend = _RecordingBackend();
        final stem = Stem(
          broker: broker,
          backend: backend,
          tasks: [const _StubTaskHandler()],
        );

        final id = await stem.enqueueVersionedJson(
          'sample.task',
          const _CodecTaskArgs('encoded'),
          version: 2,
        );

        expect(id, isNotEmpty);
        expect(broker.published.single.envelope.args, {
          PayloadCodec.versionKey: 2,
          'value': 'encoded',
        });
        expect(backend.records.single.id, id);
        expect(backend.records.single.state, TaskState.queued);
      },
    );

    test(
      'enqueueCall uses definition encoder metadata on producer-only paths',
      () async {
        final broker = _RecordingBroker();
        final backend = _RecordingBackend();
        final stem = Stem(
          broker: broker,
          backend: backend,
          encoderRegistry: ensureTaskPayloadEncoderRegistry(
            null,
            additionalEncoders: [_codecReceiptEncoder, _passthroughMapEncoder],
          ),
        );
        final definition = TaskDefinition<({String value}), _CodecReceipt>(
          name: 'sample.typed.encoded',
          encodeArgs: (args) => {'value': args.value},
          metadata: const TaskMetadata(
            argsEncoder: _passthroughMapEncoder,
            resultEncoder: _codecReceiptEncoder,
          ),
        );

        final id = await stem.enqueueCall(
          definition.buildCall((value: 'encoded')),
        );

        expect(
          broker.published.single.envelope.headers[stemArgsEncoderHeader],
          _passthroughMapEncoder.id,
        );
        expect(
          backend.records.single.meta[stemResultEncoderMetaKey],
          _codecReceiptEncoder.id,
        );
        expect(backend.records.single.id, id);
      },
    );

    test(
      'codec-backed task definitions attach result encoder metadata by default',
      () async {
        final broker = _RecordingBroker();
        final backend = _RecordingBackend();
        final stem = Stem(broker: broker, backend: backend);
        final definition = TaskDefinition<_CodecTaskArgs, _CodecReceipt>.codec(
          name: 'sample.codec.result',
          argsCodec: _codecTaskArgsCodec,
          resultCodec: _codecReceiptCodec,
        );

        final id = await stem.enqueueCall(
          definition.buildCall(const _CodecTaskArgs('encoded')),
        );

        expect(
          backend.records.single.meta[stemResultEncoderMetaKey],
          endsWith('.result.codec'),
        );
        expect(backend.records.single.id, id);
      },
    );

    test(
      'versioned json task definitions can derive versioned result metadata',
      () async {
        final broker = _RecordingBroker();
        final backend = _RecordingBackend();
        final stem = Stem(broker: broker, backend: backend);
        final definition =
            TaskDefinition<_CodecTaskArgs, _CodecReceipt>.versionedJson(
              name: 'sample.versioned_json.result',
              version: 2,
              decodeResultVersionedJson: _CodecReceipt.fromVersionedJson,
            );

        final id = await stem.enqueueCall(
          definition.buildCall(const _CodecTaskArgs('encoded')),
        );

        expect(
          backend.records.single.meta[stemResultEncoderMetaKey],
          endsWith('.result.codec'),
        );
        expect(backend.records.single.id, id);
      },
    );

    test(
      'versioned json registry task definitions can derive versioned result '
      'metadata',
      () async {
        final broker = _RecordingBroker();
        final backend = _RecordingBackend();
        final stem = Stem(broker: broker, backend: backend);
        final definition =
            TaskDefinition<_CodecTaskArgs, _CodecReceipt>.versionedJsonRegistry(
              name: 'sample.versioned_json.registry.result',
              version: 2,
              resultRegistry: _codecReceiptRegistry,
            );

        final id = await stem.enqueueCall(
          definition.buildCall(const _CodecTaskArgs('encoded')),
        );

        expect(
          backend.records.single.meta[stemResultEncoderMetaKey],
          endsWith('.result.codec'),
        );
        expect(backend.records.single.id, id);
      },
    );

    test(
      'versioned map task definitions can derive versioned result metadata',
      () async {
        final broker = _RecordingBroker();
        final backend = _RecordingBackend();
        final stem = Stem(broker: broker, backend: backend);
        final definition =
            TaskDefinition<_CodecTaskArgs, _CodecReceipt>.versionedMap(
          name: 'sample.versioned_map.result',
          version: 2,
          encodeArgs: (args) => {'legacy_value': args.value},
          decodeResultVersionedJson: _CodecReceipt.fromVersionedJson,
        );

        final id = await stem.enqueueCall(
          definition.buildCall(const _CodecTaskArgs('encoded')),
        );

        expect(
          backend.records.single.meta[stemResultEncoderMetaKey],
          endsWith('.result.codec'),
        );
        expect(backend.records.single.id, id);
      },
    );

    test(
      'json task definitions can derive versioned result metadata',
      () async {
        final broker = _RecordingBroker();
        final backend = _RecordingBackend();
        final stem = Stem(broker: broker, backend: backend);
        final definition = TaskDefinition<_CodecTaskArgs, _CodecReceipt>.json(
          name: 'sample.json.result.versioned',
          decodeResultVersionedJson: _CodecReceipt.fromVersionedJson,
          defaultDecodeVersion: 2,
        );

        final id = await stem.enqueueCall(
          definition.buildCall(const _CodecTaskArgs('encoded')),
        );

        expect(
          backend.records.single.meta[stemResultEncoderMetaKey],
          endsWith('.result.codec'),
        );
        expect(backend.records.single.id, id);
      },
    );

    test(
      'enqueueCall publishes no-arg definitions without fake empty maps',
      () async {
        final broker = _RecordingBroker();
        final backend = _RecordingBackend();
        final stem = Stem(broker: broker, backend: backend);
        final definition = TaskDefinition.noArgs<String>(
          name: 'sample.no_args',
          defaultOptions: const TaskOptions(queue: 'typed'),
        );

        final id = await definition.enqueue(stem);

        expect(id, isNotEmpty);
        expect(broker.published.single.envelope.name, 'sample.no_args');
        expect(broker.published.single.envelope.queue, 'typed');
        expect(broker.published.single.envelope.args, isEmpty);
        expect(backend.records.single.id, id);
        expect(backend.records.single.state, TaskState.queued);
      },
    );

    test('uses handler default queue when raw enqueue omits options', () async {
      final broker = _RecordingBroker();
      final stem = Stem(
        broker: broker,
        tasks: [
          const _StubTaskHandler(
            options: TaskOptions(queue: 'emails'),
          ),
        ],
      );

      await stem.enqueue('sample.task', args: {'value': 'ok'});

      expect(broker.published.single.envelope.queue, 'emails');
    });

    test(
      'uses handler publish defaults for priority visibility and retry policy',
      () async {
        final broker = _RecordingBroker();
        final backend = _RecordingBackend();
        final stem = Stem(
          broker: broker,
          backend: backend,
          tasks: [
            const _StubTaskHandler(
              options: TaskOptions(
                queue: 'emails',
                priority: 7,
                visibilityTimeout: Duration(seconds: 45),
                retryPolicy: TaskRetryPolicy(maxRetries: 9),
              ),
            ),
          ],
        );

        await stem.enqueue('sample.task', args: {'value': 'ok'});

        expect(broker.published.single.envelope.queue, 'emails');
        expect(broker.published.single.envelope.priority, 7);
        expect(
          broker.published.single.envelope.visibilityTimeout,
          const Duration(seconds: 45),
        );
        expect(broker.published.single.envelope.maxRetries, 9);
        expect(
          backend.records.single.meta['stem.retryPolicy'],
          containsPair('maxRetries', 9),
        );
      },
    );

    test('explicit task options override handler defaults', () async {
      final broker = _RecordingBroker();
      final stem = Stem(
        broker: broker,
        tasks: [
          const _StubTaskHandler(
            options: TaskOptions(queue: 'emails', priority: 7),
          ),
        ],
      );

      await stem.enqueue(
        'sample.task',
        args: {'value': 'ok'},
        options: const TaskOptions(queue: 'custom', priority: 3),
      );

      expect(broker.published.single.envelope.queue, 'custom');
      expect(broker.published.single.envelope.priority, 3);
    });

    test('enqueue options override handler routing defaults', () async {
      final broker = _RecordingBroker();
      final stem = Stem(
        broker: broker,
        tasks: [
          const _StubTaskHandler(
            options: TaskOptions(queue: 'emails', priority: 7),
          ),
        ],
      );

      await stem.enqueue(
        'sample.task',
        args: {'value': 'ok'},
        enqueueOptions: const TaskEnqueueOptions(queue: 'audit', priority: 5),
      );

      expect(broker.published.single.envelope.queue, 'audit');
      expect(broker.published.single.envelope.priority, 5);
    });

    test(
      'no-arg task definitions can attach codec-backed result metadata',
      () async {
        final broker = _RecordingBroker();
        final backend = _RecordingBackend();
        final stem = Stem(broker: broker, backend: backend);
        final definition = TaskDefinition.noArgsCodec<_CodecReceipt>(
          name: 'sample.no_args.codec',
          resultCodec: _codecReceiptCodec,
        );

        final id = await definition.enqueue(stem);

        expect(
          backend.records.single.meta[stemResultEncoderMetaKey],
          endsWith('.result.codec'),
        );
        expect(backend.records.single.id, id);
      },
    );

    test(
      'no-arg task definitions can derive json-backed result metadata',
      () async {
        final broker = _RecordingBroker();
        final backend = _RecordingBackend();
        final stem = Stem(broker: broker, backend: backend);
        final definition = TaskDefinition.noArgsJson<_CodecReceipt>(
          name: 'sample.no_args.json',
          decodeResult: _CodecReceipt.fromJson,
        );

        final id = await definition.enqueue(stem);

        expect(
          backend.records.single.meta[stemResultEncoderMetaKey],
          endsWith('.result.codec'),
        );
        expect(backend.records.single.id, id);
      },
    );

    test(
      'no-arg task definitions can derive versioned json-backed result'
      ' metadata',
      () async {
        final broker = _RecordingBroker();
        final backend = _RecordingBackend();
        final stem = Stem(broker: broker, backend: backend);
        final definition = TaskDefinition.noArgsVersionedJson<_CodecReceipt>(
          name: 'sample.no_args.versioned_json',
          version: 2,
          decodeResult: _CodecReceipt.fromVersionedJson,
        );

        final id = await definition.enqueue(stem);

        expect(
          backend.records.single.meta[stemResultEncoderMetaKey],
          endsWith('.result.codec'),
        );
        expect(backend.records.single.id, id);
      },
    );
  });

  group('TaskCall helpers', () {
    test('TaskDefinition.enqueue enqueues typed args directly', () async {
      final broker = _RecordingBroker();
      final backend = _RecordingBackend();
      final stem = Stem(broker: broker, backend: backend);
      final definition = TaskDefinition<({String value}), String>(
        name: 'sample.task_definition_enqueue',
        encodeArgs: (args) => {'value': args.value},
        defaultOptions: const TaskOptions(queue: 'typed'),
      );

      final taskId = await TaskEnqueueScope.run({'traceId': 'scope-1'}, () {
        return definition.enqueue(stem, (value: 'ok'));
      });

      expect(taskId, isNotEmpty);
      expect(
        broker.published.single.envelope.name,
        'sample.task_definition_enqueue',
      );
      expect(broker.published.single.envelope.queue, 'typed');
      expect(
        broker.published.single.envelope.meta,
        containsPair('traceId', 'scope-1'),
      );
    });

    test('enqueue enqueues typed calls with scoped metadata', () async {
      final broker = _RecordingBroker();
      final backend = _RecordingBackend();
      final stem = Stem(broker: broker, backend: backend);
      final definition = TaskDefinition<({String value}), String>(
        name: 'sample.task_call',
        encodeArgs: (args) => {'value': args.value},
        defaultOptions: const TaskOptions(queue: 'typed'),
      );

      final taskId = await TaskEnqueueScope.run({'traceId': 'scope-1'}, () {
        return definition.enqueue(stem, (value: 'ok'));
      });

      expect(taskId, isNotEmpty);
      expect(broker.published.single.envelope.name, 'sample.task_call');
      expect(broker.published.single.envelope.queue, 'typed');
      expect(
        broker.published.single.envelope.meta,
        containsPair('traceId', 'scope-1'),
      );
    });

    test('enqueueAndWait returns typed results', () async {
      final broker = _RecordingBroker();
      final backend = _RecordingBackend();
      final stem = Stem(broker: broker, backend: backend);
      final definition = TaskDefinition<({String value}), String>(
        name: 'sample.task_call_wait',
        encodeArgs: (args) => {'value': args.value},
      );

      unawaited(
        Future<void>(() async {
          while (broker.published.isEmpty) {
            await Future<void>.delayed(Duration.zero);
          }
          final taskId = broker.published.single.envelope.id;
          await backend.set(taskId, TaskState.succeeded, payload: 'done');
        }),
      );

      final result = await definition.enqueueAndWait(
        stem,
        (value: 'ok'),
        timeout: const Duration(seconds: 1),
      );

      expect(result?.isSucceeded, isTrue);
      expect(result?.value, 'done');
    });

    test('TaskDefinition.enqueueAndWait returns typed results', () async {
      final broker = _RecordingBroker();
      final backend = _RecordingBackend();
      final stem = Stem(broker: broker, backend: backend);
      final definition = TaskDefinition<({String value}), String>(
        name: 'sample.task_definition_wait',
        encodeArgs: (args) => {'value': args.value},
      );

      unawaited(
        Future<void>(() async {
          while (broker.published.isEmpty) {
            await Future<void>.delayed(Duration.zero);
          }
          final taskId = broker.published.single.envelope.id;
          await backend.set(taskId, TaskState.succeeded, payload: 'done');
        }),
      );

      final result = await definition.enqueueAndWait(
        stem,
        (value: 'ok'),
        timeout: const Duration(seconds: 1),
      );

      expect(result?.isSucceeded, isTrue);
      expect(result?.value, 'done');
    });
  });

  group('TaskDefinition.waitFor', () {
    test('uses definition decoding rules', () async {
      final backend = _codecAwareBackend();
      final stem = _codecAwareStem(backend);

      await backend.set(
        'task-definition-wait',
        TaskState.succeeded,
        payload: const _CodecReceipt('receipt-definition'),
        meta: {stemResultEncoderMetaKey: _codecReceiptEncoder.id},
      );

      final result = await _codecReceiptDefinition.waitFor(
        stem,
        'task-definition-wait',
      );

      expect(result?.value?.id, 'receipt-definition');
      expect(result?.rawPayload, isA<_CodecReceipt>());
    });

    test('supports no-arg task definitions', () async {
      final backend = InMemoryResultBackend();
      final stem = Stem(broker: _RecordingBroker(), backend: backend);
      final definition = TaskDefinition.noArgsJson<_CodecReceipt>(
        name: 'no-args.wait',
        decodeResult: _CodecReceipt.fromJson,
      );

      await backend.set(
        'task-no-args-wait',
        TaskState.succeeded,
        payload: const _CodecReceipt('done'),
        meta: {stemResultEncoderMetaKey: _codecReceiptEncoder.id},
      );

      final result = await definition.waitFor(stem, 'task-no-args-wait');

      expect(result?.value?.id, 'done');
      expect(result?.rawPayload, isA<_CodecReceipt>());
    });

    test('supports versioned no-arg task definitions', () async {
      final backend = InMemoryResultBackend();
      final stem = Stem(broker: _RecordingBroker(), backend: backend);
      final definition = TaskDefinition.noArgsVersionedJson<_CodecReceipt>(
        name: 'no-args.versioned.wait',
        version: 2,
        decodeResult: _CodecReceipt.fromVersionedJson,
      );

      await backend.set(
        'task-no-args-versioned-wait',
        TaskState.succeeded,
        payload: {'id': 'done', PayloadCodec.versionKey: 2},
        meta: {stemResultEncoderMetaKey: _codecReceiptEncoder.id},
      );

      final result = await definition.waitFor(
        stem,
        'task-no-args-versioned-wait',
      );

      expect(result?.value?.id, 'done-v2');
      expect(result?.rawPayload, isA<Map<String, Object?>>());
    });

    test('supports versioned argful task definitions', () async {
      final backend = InMemoryResultBackend();
      final stem = Stem(broker: _RecordingBroker(), backend: backend);
      final definition =
          TaskDefinition<_CodecTaskArgs, _CodecReceipt>.versionedJson(
            name: 'args.versioned.wait',
            version: 2,
            decodeResultVersionedJson: _CodecReceipt.fromVersionedJson,
          );

      await backend.set(
        'task-args-versioned-wait',
        TaskState.succeeded,
        payload: {'id': 'done', PayloadCodec.versionKey: 2},
        meta: {stemResultEncoderMetaKey: _codecReceiptEncoder.id},
      );

      final result = await definition.waitFor(
        stem,
        'task-args-versioned-wait',
      );

      expect(result?.value?.id, 'done-v2');
      expect(result?.rawPayload, isA<Map<String, Object?>>());
    });

    test(
      'supports json argful task definitions with versioned results',
      () async {
      final backend = InMemoryResultBackend();
      final stem = Stem(broker: _RecordingBroker(), backend: backend);
      final definition = TaskDefinition<_CodecTaskArgs, _CodecReceipt>.json(
        name: 'args.json.versioned.wait',
        decodeResultVersionedJson: _CodecReceipt.fromVersionedJson,
        defaultDecodeVersion: 2,
      );

      await backend.set(
        'task-args-json-versioned-wait',
        TaskState.succeeded,
        payload: {'id': 'done', PayloadCodec.versionKey: 2},
        meta: {stemResultEncoderMetaKey: _codecReceiptEncoder.id},
      );

      final result = await definition.waitFor(
        stem,
        'task-args-json-versioned-wait',
      );

      expect(result?.value?.id, 'done-v2');
      expect(result?.rawPayload, isA<Map<String, Object?>>());
    });

    test('enqueueAndWait supports no-arg task definitions', () async {
      final broker = _RecordingBroker();
      final backend = _RecordingBackend();
      final stem = Stem(broker: broker, backend: backend);
      final definition = TaskDefinition.noArgs<String>(name: 'no-args.enqueue');

      unawaited(
        Future<void>(() async {
          while (broker.published.isEmpty) {
            await Future<void>.delayed(Duration.zero);
          }
          final taskId = broker.published.single.envelope.id;
          await backend.set(taskId, TaskState.succeeded, payload: 'done');
        }),
      );

      final result = await definition.enqueueAndWait(
        stem,
        timeout: const Duration(seconds: 1),
      );

      expect(result?.value, 'done');
      expect(result?.rawPayload, 'done');
    });
  });

  group('TaskDefinition.waitFor', () {
    test('does not double decode codec-backed terminal results', () async {
      final backend = _codecAwareBackend();
      final stem = _codecAwareStem(backend);

      await backend.set(
        'task-terminal',
        TaskState.succeeded,
        payload: const _CodecReceipt('receipt-terminal'),
        meta: {stemResultEncoderMetaKey: _codecReceiptEncoder.id},
      );

      final result = await _codecReceiptDefinition.waitFor(
        stem,
        'task-terminal',
      );

      expect(result?.value?.id, 'receipt-terminal');
      expect(result?.rawPayload, isA<_CodecReceipt>());
    });

    test('does not double decode codec-backed watched results', () async {
      final backend = _codecAwareBackend();
      final stem = _codecAwareStem(backend);

      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 20), () async {
          await backend.set(
            'task-watched',
            TaskState.succeeded,
            payload: const _CodecReceipt('receipt-watched'),
            meta: {stemResultEncoderMetaKey: _codecReceiptEncoder.id},
          );
        }),
      );

      final result = await _codecReceiptDefinition.waitFor(
        stem,
        'task-watched',
        timeout: const Duration(seconds: 1),
      );

      expect(result?.value?.id, 'receipt-watched');
      expect(result?.rawPayload, isA<_CodecReceipt>());
    });
  });

  group('Stem.waitForTask', () {
    test('supports decodeJson for low-level DTO waits', () async {
      final backend = InMemoryResultBackend();
      final stem = Stem(broker: _RecordingBroker(), backend: backend);

      await backend.set(
        'task-json-wait',
        TaskState.succeeded,
        payload: const {'id': 'receipt-json'},
      );

      final result = await stem.waitForTask<_CodecReceipt>(
        'task-json-wait',
        decodeJson: _CodecReceipt.fromJson,
      );

      expect(result?.isSucceeded, isTrue);
      expect(result?.requiredValue().id, 'receipt-json');
      expect(result?.rawPayload, const {'id': 'receipt-json'});
    });

    test('supports decodeVersionedJson for low-level DTO waits', () async {
      final backend = InMemoryResultBackend();
      final stem = Stem(broker: _RecordingBroker(), backend: backend);

      await backend.set(
        'task-versioned-json-wait',
        TaskState.succeeded,
        payload: const {
          PayloadCodec.versionKey: 2,
          'id': 'receipt-versioned-json',
        },
      );

      final result = await stem.waitForTask<_CodecReceipt>(
        'task-versioned-json-wait',
        decodeVersionedJson: _CodecReceipt.fromVersionedJson,
      );

      expect(result?.isSucceeded, isTrue);
      expect(result?.requiredValue().id, 'receipt-versioned-json-v2');
      expect(result?.rawPayload, const {
        PayloadCodec.versionKey: 2,
        'id': 'receipt-versioned-json',
      });
    });
  });
}

ResultBackend _codecAwareBackend() {
  final registry = ensureTaskPayloadEncoderRegistry(
    null,
    additionalEncoders: [_codecReceiptEncoder],
  );
  return withTaskPayloadEncoder(InMemoryResultBackend(), registry);
}

Stem _codecAwareStem(ResultBackend backend) {
  return Stem(
    broker: _RecordingBroker(),
    backend: backend,
    encoderRegistry: ensureTaskPayloadEncoderRegistry(
      null,
      additionalEncoders: [_codecReceiptEncoder],
    ),
  );
}

class _CodecReceipt {
  const _CodecReceipt(this.id);

  factory _CodecReceipt.fromJson(Map<String, Object?> json) {
    return _CodecReceipt(json['id']! as String);
  }

  factory _CodecReceipt.fromVersionedJson(
    Map<String, Object?> json,
    int version,
  ) {
    return _CodecReceipt('${json['id']! as String}-v$version');
  }

  factory _CodecReceipt.fromV2Json(Map<String, dynamic> json) {
    return _CodecReceipt('${json['id']! as String}-v2');
  }

  final String id;

  Map<String, Object?> toJson() => {'id': id};
}

class _EnvelopeArgs {
  const _EnvelopeArgs(this.value);

  factory _EnvelopeArgs.fromJson(Map<String, dynamic> json) {
    return _EnvelopeArgs(json['value'] as int);
  }

  factory _EnvelopeArgs.fromVersionedJson(
    Map<String, dynamic> json,
    int version,
  ) {
    expect(version, 2);
    return _EnvelopeArgs.fromJson(json);
  }

  final int value;
}

class _EnvelopeMeta {
  const _EnvelopeMeta(this.label);

  factory _EnvelopeMeta.fromJson(Map<String, dynamic> json) {
    return _EnvelopeMeta(json['label'] as String);
  }

  factory _EnvelopeMeta.fromVersionedJson(
    Map<String, dynamic> json,
    int version,
  ) {
    expect(version, 2);
    return _EnvelopeMeta.fromJson(json);
  }

  final String label;
}

const _codecReceiptCodec = PayloadCodec<_CodecReceipt>.json(
  decode: _CodecReceipt.fromJson,
  typeName: '_CodecReceipt',
);

const _codecReceiptRegistry = PayloadVersionRegistry<_CodecReceipt>(
  decoders: <int, _CodecReceipt Function(Map<String, dynamic>)>{
    1: _CodecReceipt.fromJson,
    2: _CodecReceipt.fromV2Json,
  },
  defaultVersion: 1,
);

const _codecReceiptEncoder = CodecTaskPayloadEncoder<_CodecReceipt>(
  idValue: 'test.codec.receipt',
  codec: _codecReceiptCodec,
);

const _passthroughMapEncoder = _MapPassthroughEncoder('test.args.map');

final _codecReceiptDefinition =
    TaskDefinition<Map<String, Object?>, _CodecReceipt>(
      name: 'codec.receipt',
      encodeArgs: (args) => args,
      decodeResult: _codecReceiptCodec.decode,
    );

class _CodecTaskArgs {
  const _CodecTaskArgs(this.value);

  final String value;

  Map<String, Object?> toJson() => {'value': value};
}

const _codecTaskArgsCodec = PayloadCodec<_CodecTaskArgs>.map(
  encode: _encodeCodecTaskArgs,
  decode: _decodeCodecTaskArgs,
  typeName: '_CodecTaskArgs',
);

Object? _encodeCodecTaskArgs(_CodecTaskArgs value) => value.toJson();

_CodecTaskArgs _decodeCodecTaskArgs(Object? payload) {
  final map = Map<String, Object?>.from(payload! as Map);
  return _CodecTaskArgs(map['value']! as String);
}

class _StubTaskHandler implements TaskHandler<void> {
  const _StubTaskHandler({
    TaskOptions options = const TaskOptions(),
    TaskMetadata metadata = const TaskMetadata(),
  }) : _taskOptions = options,
       _taskMetadata = metadata;

  final TaskOptions _taskOptions;
  final TaskMetadata _taskMetadata;

  @override
  String get name => 'sample.task';

  @override
  TaskOptions get options => _taskOptions;

  @override
  TaskMetadata get metadata => _taskMetadata;

  @override
  TaskEntrypoint? get isolateEntrypoint => null;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {}
}

class _RecordingBroker implements Broker {
  final List<Delivery> published = [];

  @override
  Future<void> ack(Delivery delivery) async {}

  @override
  Future<void> deadLetter(
    Delivery delivery, {
    String? reason,
    Map<String, Object?>? meta,
  }) async {}

  @override
  Future<void> nack(Delivery delivery, {bool requeue = true}) async {}

  @override
  Future<void> publish(Envelope envelope, {RoutingInfo? routing}) async {
    published.add(
      Delivery(envelope: envelope, receipt: 'receipt', leaseExpiresAt: null),
    );
  }

  @override
  Future<void> purge(String queue) async {}

  @override
  Stream<Delivery> consume(
    RoutingSubscription subscription, {
    int prefetch = 1,
    String? consumerGroup,
    String? consumerName,
  }) => const Stream.empty();

  @override
  Future<void> extendLease(Delivery delivery, Duration by) async {}

  @override
  Future<int?> pendingCount(String queue) async => published.length;

  @override
  Future<int?> inflightCount(String queue) async => 0;

  @override
  bool get supportsDelayed => true;

  @override
  bool get supportsPriority => false;

  @override
  Future<DeadLetterPage> listDeadLetters(
    String queue, {
    int limit = 50,
    int offset = 0,
  }) async => const DeadLetterPage(entries: []);

  @override
  Future<DeadLetterEntry?> getDeadLetter(String queue, String id) async => null;

  @override
  Future<DeadLetterReplayResult> replayDeadLetters(
    String queue, {
    int limit = 50,
    DateTime? since,
    Duration? delay,
    bool dryRun = false,
  }) async => DeadLetterReplayResult(entries: const [], dryRun: dryRun);

  @override
  Future<int> purgeDeadLetters(
    String queue, {
    DateTime? since,
    int? limit,
  }) async => 0;

  @override
  Future<void> close() async {}
}

class _MapPassthroughEncoder implements TaskPayloadEncoder {
  const _MapPassthroughEncoder(this.id);

  @override
  final String id;

  @override
  Object? encode(Object? value) => value;

  @override
  Object? decode(Object? value) => value;
}

class _RecordingBackend implements ResultBackend {
  final List<TaskStatus> records = [];
  final Map<String, StreamController<TaskStatus>> _controllers = {};
  final Map<String, GroupStatus> _groups = {};
  WorkerHeartbeat? lastHeartbeat;
  final Set<String> _claimedChords = {};

  @override
  Future<TaskStatus?> get(String taskId) async => records
      .cast<TaskStatus?>()
      .firstWhere((e) => e?.id == taskId, orElse: () => null);

  @override
  Stream<TaskStatus> watch(String taskId) {
    final controller = _controllers.putIfAbsent(
      taskId,
      StreamController<TaskStatus>.broadcast,
    );
    return controller.stream;
  }

  @override
  Future<TaskStatusPage> listTaskStatuses(
    TaskStatusListRequest request,
  ) async {
    return const TaskStatusPage(items: []);
  }

  @override
  Future<void> set(
    String taskId,
    TaskState state, {
    Object? payload,
    TaskError? error,
    int attempt = 0,
    Map<String, Object?> meta = const {},
    Duration? ttl,
  }) async {
    records.add(
      TaskStatus(
        id: taskId,
        state: state,
        payload: payload,
        error: error,
        attempt: attempt,
        meta: meta,
      ),
    );
    _controllers[taskId]?.add(records.last);
  }

  @override
  Future<void> initGroup(GroupDescriptor descriptor) async {
    _groups[descriptor.id] = GroupStatus(
      id: descriptor.id,
      expected: descriptor.expected,
      meta: descriptor.meta,
    );
  }

  @override
  Future<void> setWorkerHeartbeat(WorkerHeartbeat heartbeat) async {
    lastHeartbeat = heartbeat;
  }

  @override
  Future<WorkerHeartbeat?> getWorkerHeartbeat(String workerId) async {
    return lastHeartbeat?.workerId == workerId ? lastHeartbeat : null;
  }

  @override
  Future<List<WorkerHeartbeat>> listWorkerHeartbeats() async {
    return lastHeartbeat == null ? const [] : [lastHeartbeat!];
  }

  @override
  Future<GroupStatus?> addGroupResult(String groupId, TaskStatus status) async {
    final existing = _groups[groupId];
    if (existing == null) return null;
    final updatedResults = Map<String, TaskStatus>.from(existing.results)
      ..[status.id] = status;
    final updated = GroupStatus(
      id: existing.id,
      expected: existing.expected,
      results: updatedResults,
      meta: existing.meta,
    );
    _groups[groupId] = updated;
    return updated;
  }

  @override
  Future<GroupStatus?> getGroup(String groupId) async => _groups[groupId];

  @override
  Future<bool> claimChord(
    String groupId, {
    String? callbackTaskId,
    DateTime? dispatchedAt,
  }) async {
    final added = _claimedChords.add(groupId);
    if (!added) return false;
    final existing = _groups[groupId];
    if (existing != null) {
      final meta = Map<String, Object?>.from(existing.meta);
      if (callbackTaskId != null) {
        meta[ChordMetadata.callbackTaskId] = callbackTaskId;
      }
      if (dispatchedAt != null) {
        meta[ChordMetadata.dispatchedAt] = dispatchedAt.toIso8601String();
      }
      _groups[groupId] = GroupStatus(
        id: existing.id,
        expected: existing.expected,
        results: existing.results,
        meta: meta,
      );
    }
    return true;
  }

  @override
  Future<void> expire(String taskId, Duration ttl) async {}

  @override
  Future<void> close() async {}
}
