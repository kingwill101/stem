import 'dart:async';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  test('zero-delay retries are durable wakeups, not local loops', () async {
    var prepared = 0;
    var attempts = 0;
    final workflow = HostedWorkflow<String, String>(
      name: 'retry.zero',
      run: (flow, input) async {
        await flow.step('prepare', () => ++prepared);
        return flow.step('unstable', () {
          attempts++;
          if (attempts < 3) throw StateError('retry');
          return input;
        }, retry: const WorkflowRetryPolicy(maxAttempts: 3));
      },
    );
    final host = await WorkflowHost.inMemory(workflows: [workflow]);
    addTearDown(host.close);
    expect(
      await host
          .execute(workflow, 'done')
          .timeout(
            const Duration(seconds: 5),
          ),
      'done',
    );
    expect(attempts, 3);
    expect(prepared, 1);
  });

  test(
    'exhausted step budgets do not reset with another observation',
    () async {
      var attempts = 0;
      final workflow = HostedWorkflow<String, String>(
        name: 'retry.exhausted',
        run: (flow, _) => flow.step<String>('fail', () {
          attempts++;
          throw StateError('not available');
        }, retry: const WorkflowRetryPolicy(maxAttempts: 2)),
      );
      final host = await WorkflowHost.inMemory(workflows: [workflow]);
      addTearDown(host.close);
      final run = await host.submit(workflow, 'input');
      await expectLater(
        run.result.timeout(const Duration(seconds: 5)),
        throwsA(isA<HostedWorkflowFailure>()),
      );
      final observed = await host.observe(workflow, run.id);
      await expectLater(observed.result, throwsA(isA<HostedWorkflowFailure>()));
      expect(attempts, 2);
    },
  );

  test(
    'automatic failure cleanup receives snapshots in reverse order',
    () async {
      final cleaned = <String>[];
      final undo = HostedCompensation<String>(
        name: 'undo',
        run: (_, value) => cleaned.add(value),
      );
      var actions = 0;
      final workflow = HostedWorkflow<String, String>(
        name: 'compensation.reverse',
        compensations: [undo],
        run: (flow, input) async {
          await flow.step('a', () {
            actions++;
            return '$input:a';
          }, compensation: undo);
          await flow.step('b', () {
            actions++;
            return '$input:b';
          }, compensation: undo);
          return flow.step<String>(
            'fail',
            () => throw StateError('final failure'),
            retry: const WorkflowRetryPolicy(),
          );
        },
      );
      final host = await WorkflowHost.inMemory(workflows: [workflow]);
      addTearDown(host.close);
      final run = await host.submit(workflow, 'snapshot');
      await expectLater(run.result, throwsA(isA<HostedWorkflowFailure>()));
      await _until(
        () async => (await run.compensations()).every(
          (entry) => entry.data['state'] == 'completed',
        ),
      );
      expect(cleaned, ['snapshot:b', 'snapshot:a']);
      expect(actions, 2);
      await run.retryCompensations();
      expect(cleaned, ['snapshot:b', 'snapshot:a']);
    },
  );

  test(
    'operator retry extends cleanup budget without repeating successes',
    () async {
      final keys = <String>[];
      var cleanupAttempts = 0;
      final undo = HostedCompensation<String>(
        name: 'undo.retry',
        run: (context, _) {
          keys.add(context.idempotencyKey);
          cleanupAttempts++;
          if (cleanupAttempts == 1) throw StateError('cleanup unavailable');
        },
      );
      final workflow = HostedWorkflow<String, String>(
        name: 'compensation.retry',
        compensations: [undo],
        run: (flow, input) async {
          await flow.step('create', () => input, compensation: undo);
          return flow.step<String>(
            'fail',
            () => throw StateError('forward failed'),
            retry: const WorkflowRetryPolicy(),
          );
        },
      );
      final host = await WorkflowHost.inMemory(workflows: [workflow]);
      addTearDown(host.close);
      final run = await host.submit(workflow, 'value');
      await expectLater(run.result, throwsA(isA<HostedWorkflowFailure>()));
      await _until(
        () async =>
            (await run.compensations()).single.data['state'] == 'exhausted',
      );
      expect(cleanupAttempts, 1);
      await run.retryCompensations(additionalAttempts: 1);
      await _until(
        () async =>
            (await run.compensations()).single.data['state'] == 'completed',
      );
      final entry = (await run.compensations()).single;
      expect(entry.data['attempts'], 2);
      expect(keys[0], keys[1]);
      expect((await run.status()).status, WorkflowStatus.failed);
    },
  );

  test('cancellation does not automatically run compensation', () async {
    var cleanups = 0;
    final undo = HostedCompensation<String>(
      name: 'undo.cancel',
      run: (_, _) => cleanups++,
    );
    final workflow = HostedWorkflow<String, String>(
      name: 'compensation.cancel',
      compensations: [undo],
      run: (flow, input) async {
        await flow.step('create', () => input, compensation: undo);
        await flow.awaitEvent(
          'wait',
          const WorkflowEventRef<Map<String, Object?>>(topic: 'never'),
        );
        return input;
      },
    );
    final host = await WorkflowHost.inMemory(workflows: [workflow]);
    addTearDown(host.close);
    final run = await host.submit(workflow, 'value');
    await run.watch().firstWhere(
      (view) => view.status == WorkflowStatus.suspended,
    );
    await run.cancel();
    await expectLater(run.retryCompensations(), throwsStateError);
    await host.close();
    expect(cleanups, 0);
  });
}

Future<void> _until(Future<bool> Function() condition) async {
  final deadline = Stopwatch()..start();
  while (!await condition()) {
    if (deadline.elapsed > const Duration(seconds: 5)) {
      throw TimeoutException('Journal transition did not complete.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
