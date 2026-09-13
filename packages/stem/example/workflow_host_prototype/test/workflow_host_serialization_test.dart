import 'dart:convert';

import 'package:test/test.dart';
import 'package:workflow_host_prototype/workflow_host.dart';

class _Request {
  _Request(this.amount);
  final int amount;
}

class _Receipt {
  _Receipt(this.total);
  final int total;
}

class _Convert<S, T> extends Converter<S, T> {
  _Convert(this.fn);
  final T Function(S) fn;
  @override
  T convert(S input) => fn(input);
}

class _Codec<T> extends Codec<T, Object?> {
  _Codec(T Function(Object?) decode, Object? Function(T) encode)
    : decoder = _Convert(decode),
      encoder = _Convert(encode);
  @override
  final Converter<Object?, T> decoder;
  @override
  final Converter<T, Object?> encoder;
}

PayloadCodecRegistry _registry({int offset = 0}) => PayloadCodecRegistry()
  ..register<_Request>(
    _Codec(
      (value) => _Request((value as Map)['amount'] as int),
      (value) => {'amount': value.amount + offset},
    ),
  )
  ..register<_Receipt>(
    _Codec(
      (value) => _Receipt((value as Map)['total'] as int),
      (value) => {'total': value.total},
    ),
  );

void main() {
  test(
    'host codecs cover distinct DTO input/output and nullable replay',
    () async {
      var calls = 0;
      final workflow = HostedWorkflow<_Request?, _Receipt?>(
        name: 'dto',
        run: (flow, input) async {
          for (var i = 0; i < 2; i++) {
            expect(
              await flow.step<_Receipt?>('null', () {
                calls++;
                return null;
              }),
              isNull,
            );
          }
          final result = await flow.step<_Receipt?>(
            'receipt',
            () => input == null ? null : _Receipt(input.amount + 1),
          );
          final replay = await flow.step<_Receipt?>(
            'receipt',
            () => throw StateError('Must replay'),
          );
          expect(replay?.total, result?.total);
          return result;
        },
      );
      await WorkflowHost.run<void>(
        workflows: [workflow],
        codecs: _registry(),
        body: (host) async {
          expect((await host.execute(workflow, _Request(41)))?.total, 42);
          expect(await host.execute(workflow, null), isNull);
          expect(calls, 2);
        },
      );
    },
  );

  test('same definition binds independently on separate hosts', () async {
    final workflow = HostedWorkflow<_Request, _Receipt>(
      name: 'independent',
      run: (_, input) async => _Receipt(input.amount),
    );
    final first = await WorkflowHost.inMemory(
      workflows: [workflow],
      codecs: _registry(),
    );
    addTearDown(first.close);
    final second = await WorkflowHost.inMemory(
      workflows: [workflow],
      codecs: _registry(offset: 10),
    );
    addTearDown(second.close);
    expect((await first.execute(workflow, _Request(1))).total, 1);
    expect((await second.execute(workflow, _Request(1))).total, 11);
    expect((await first.execute(workflow, _Request(1))).total, 1);
  });

  test(
    'String registration overrides defaults host-wide without snapshot leaks',
    () async {
      final encoded = <String>[];
      final decoded = <String>[];
      final registry = PayloadCodecRegistry();
      final workflow = HostedWorkflow<String, String>(
        name: 'text',
        run: (flow, input) => flow.step('text', () => '$input!'),
      );
      final original = await WorkflowHost.inMemory(
        workflows: [workflow],
        codecs: registry,
      );
      addTearDown(original.close);
      registry.register<String>(
        _Codec(
          (value) {
            final text = (value as Map)['text'] as String;
            decoded.add(text);
            return text;
          },
          (value) {
            encoded.add(value);
            return {'text': value};
          },
        ),
      );
      final customized = await WorkflowHost.inMemory(
        workflows: [workflow],
        codecs: registry,
      );
      addTearDown(customized.close);
      expect(await original.execute(workflow, 'first'), 'first!');
      expect(encoded, isEmpty);
      expect(decoded, isEmpty);
      expect(await customized.execute(workflow, 'second'), 'second!');
      expect(encoded, ['second', 'second!', 'second!']);
      expect(decoded, ['second', 'second!', 'second!']);
    },
  );

  test('missing DTO codec fails during registration, before startup', () async {
    final workflow = HostedWorkflow<_Request, String>(
      name: 'missing',
      run: (_, _) async => 'unused',
    );
    await expectLater(
      WorkflowHost.inMemory(workflows: [workflow]),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Codec<_Request, Object?>'),
        ),
      ),
    );
  });

  test('unsupported JSON input is rejected at submission', () async {
    final workflow = HostedWorkflow<Object?, String>(
      name: 'invalid',
      run: (_, _) async => 'unused',
    );
    await WorkflowHost.run<void>(
      workflows: [workflow],
      body: (host) async {
        await expectLater(
          host.execute(workflow, {'nested': _Request(1)}),
          throwsFormatException,
        );
      },
    );
  });
}
