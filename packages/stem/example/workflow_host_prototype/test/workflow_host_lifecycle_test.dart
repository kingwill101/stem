import 'dart:async';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

Future<T> _withHost<T>({
  required Iterable<HostedDefinition> workflows,
  required Future<T> Function(WorkflowHost host) body,
}) async {
  final host = await WorkflowHost.inMemory(workflows: workflows);
  try {
    return await body(host);
  } finally {
    await host.close();
  }
}

void main() {
  test(
    'close wins when an in-flight observation completes after close',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final workflow = HostedWorkflow<int, int>(
        name: 'close-race',
        run: (_, value) async {
          entered.complete();
          await release.future;
          return value;
        },
      );
      final host = await WorkflowHost.inMemory(workflows: [workflow]);
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        await host.close();
      });
      final submitted = host.submit(workflow, 42);
      await entered.future;
      final run = await submitted;
      final observed = expectLater(run.result, throwsStateError);
      final closing = host.close();
      // Release immediately, while waitForCompletion is still in flight. Waiting
      // for the observation to reject first would miss the reviewed race.
      release.complete();
      await observed;
      await closing;
    },
  );

  test('closing does not change an already settled result', () async {
    final workflow = HostedWorkflow<int, int>(
      name: 'settled',
      run: (_, value) async => value,
    );
    final host = await WorkflowHost.inMemory(workflows: [workflow]);
    addTearDown(host.close);
    final run = await host.submit(workflow, 42);
    expect(await run.result, 42);
    await host.close();
    expect(await run.result, 42);
  });

  test('scope preserves body error identity and original stack', () async {
    final primary = StateError('body failed');
    final originalStack = StackTrace.fromString('original body stack');
    late WorkflowHost captured;
    try {
      await _withHost<void>(
        workflows: [],
        body: (host) async {
          captured = host;
          Error.throwWithStackTrace(primary, originalStack);
        },
      );
      fail('Expected the body error');
    } catch (error, stack) {
      expect(error, same(primary));
      expect(stack.toString(), originalStack.toString());
    }
    expect(captured.isClosed, isTrue);
    // The scope awaited cleanup, and repeated close joins the same outcome.
    await captured.close();
  });
}
