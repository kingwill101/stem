import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_memory/stem_memory.dart';
import 'package:test/test.dart';
import 'package:workflow_host_prototype/workflow_host.dart';

final class Receipt {
  Receipt(this.total);
  final int total;
}

final receiptCodec = PayloadCodec<Receipt>.map(
  encode: (value) => {'total': value.total},
  decode: (value) => Receipt(value['total'] as int),
);

HostedWorkflow<int, int> doubleWorkflow({String name = 'double'}) =>
    HostedWorkflow(name: name, run: (_, value) async => value * 2);

void main() {
  test('typed DTO inputs/results and nullable checkpoint replay', () async {
    var calls = 0;
    final nullable = PayloadCodec<String?>(
      encode: (value) => value,
      decode: (value) => value as String?,
    );
    final workflow = HostedWorkflow<Receipt, Receipt>(
      name: 'receipt',
      inputCodec: receiptCodec,
      resultCodec: receiptCodec,
      run: (flow, input) async {
        for (var i = 0; i < 2; i++) {
          final value = await flow.step<String?>('once', () {
            calls++;
            return null;
          }, codec: nullable);
          expect(value, isNull);
        }
        return Receipt(input.total + 1);
      },
    );
    await WorkflowHost.run<void>(
      workflows: [workflow],
      body: (host) async {
        final result = await host.execute(workflow, Receipt(41));
        expect(result.total, 42);
        expect(calls, 1);
      },
    );
  });

  test('multiple submissions reuse a host and keep independent ids', () async {
    final workflow = doubleWorkflow();
    await WorkflowHost.run<void>(
      workflows: [workflow],
      body: (host) async {
        final runs = await Future.wait([
          host.submit(workflow, 2),
          host.submit(workflow, 7),
        ]);
        expect(runs[0].id, isNot(runs[1].id));
        expect(await Future.wait(runs.map((run) => run.result)), [4, 14]);
        expect(await host.execute(workflow, 9), 18);
      },
    );
  });

  test(
    'nullable final results and result decoding errors reach caller',
    () async {
      final nullable = HostedWorkflow<int, String?>(
        name: 'nullable',
        run: (_, _) async => null,
      );
      final broken = HostedWorkflow<int, int>(
        name: 'broken-codec',
        resultCodec: PayloadCodec(
          encode: (value) => value,
          decode: (_) => throw const FormatException('result codec'),
        ),
        run: (_, value) async => value,
      );
      await WorkflowHost.run<void>(
        workflows: [nullable, broken],
        body: (host) async {
          expect(await host.execute(nullable, 0), isNull);
          await expectLater(host.execute(broken, 0), throwsFormatException);
        },
      );
    },
  );

  test(
    'closing during submission joins startup without stranded observation',
    () async {
      final workflow = doubleWorkflow();
      final host = await WorkflowHost.inMemory(workflows: [workflow]);
      final submitted = host.submit(workflow, 4);
      final observed = expectLater(
        submitted.then((run) => run.result),
        throwsStateError,
      );
      await host.close();
      await observed;
    },
  );

  test(
    'exhausted script failure reaches the hosted result',
    () async {
      final workflow = HostedWorkflow<int, int>(
        name: 'failure',
        run: (flow, _) =>
            flow.step<int>('fail', () => throw StateError('deliberate')),
      );
      await WorkflowHost.run<void>(
        workflows: [workflow],
        body: (host) async {
          final run = await host.submit(workflow, 0);
          await expectLater(
            run.result,
            throwsA(
              isA<HostedWorkflowFailure>()
                  .having(
                    (error) => error.status,
                    'status',
                    WorkflowStatus.failed,
                  )
                  .having(
                    (error) => error.error.toString(),
                    'error',
                    contains('deliberate'),
                  ),
            ),
          );
        },
      );
    },
    // Exercise the production retry strategy (five exponential-backoff retries),
    // not an observation timeout masquerading as workflow failure.
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('close stops observations and is idempotent', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final workflow = HostedWorkflow<int, int>(
      name: 'blocked',
      run: (_, value) async {
        entered.complete();
        await release.future;
        return value;
      },
    );
    final host = await WorkflowHost.inMemory(workflows: [workflow]);
    addTearDown(host.close);
    final submitted = host.submit(workflow, 3);
    await entered.future;
    final run = await submitted;
    final observed = expectLater(run.result, throwsStateError);
    final closing = host.close();
    expect(identical(closing, host.close()), isTrue);
    await expectLater(host.submit(workflow, 4), throwsStateError);
    var closed = false;
    unawaited(closing.then((_) => closed = true));
    expect(closed, isFalse);
    await observed;
    release.complete();
    await closing;
    expect(host.isClosed, isTrue);
  });

  test(
    'scope closes on callback error; rejects unknown and duplicate names',
    () async {
      final workflow = doubleWorkflow();
      late WorkflowHost captured;
      await expectLater(
        WorkflowHost.run<void>(
          workflows: [workflow],
          body: (host) async {
            captured = host;
            await expectLater(
              host.submit(doubleWorkflow(name: 'other'), 0),
              throwsArgumentError,
            );
            throw StateError('scope failed');
          },
        ),
        throwsStateError,
      );
      expect(captured.isClosed, isTrue);
      await expectLater(captured.execute(workflow, 1), throwsStateError);
      await expectLater(
        WorkflowHost.inMemory(workflows: [workflow, doubleWorkflow()]),
        throwsArgumentError,
      );
    },
  );

  test('underlying app uses the stem_memory compatibility adapters', () async {
    final app = await StemWorkflowApp.inMemory();
    try {
      expect(app.store, isA<InMemoryWorkflowStore>());
      expect(app.eventBus, isA<InMemoryEventBus>());
    } finally {
      await app.close();
    }
  });

  test(
    'CLI prints both branches and exits after scoped resource cleanup',
    () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'bin/main.dart',
      ]).timeout(const Duration(seconds: 30));
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, contains('Hello, Ada!'));
      expect(result.stdout, contains('Hello, stranger!'));
    },
  );
}
