import 'dart:async';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  for (final eventDeadline in [false, true]) {
    test(
      'explicit due-run resumption preserves deadline=$eventDeadline',
      () async {
        final deadline = DateTime.now().toUtc().add(const Duration(days: 1));
        final workflow = HostedWorkflow<String, String>(
          name: 'host.explicit.$eventDeadline',
          run: (context, _) async {
            if (!eventDeadline) {
              await context.sleep('wait', const Duration(days: 1));
              return 'awake';
            }
            try {
              await context.awaitEvent(
                'wait',
                const WorkflowEventRef<Map<String, Object?>>(topic: 'explicit'),
                deadline: deadline,
              );
              return 'unexpected event';
            } on TimeoutException {
              return 'deadline';
            }
          },
        );
        final app = await StemWorkflowApp.inMemory(
          workflows: [workflow.bind(PayloadCodecRegistry())],
        );
        addTearDown(app.close);
        // Use one execution path: manual calls, with no started worker/poller.
        final id = await app.startWorkflow(
          workflow.name,
          params: const {'input': 'value'},
        );
        await app.executeRun(id);
        final suspended = (await app.getRun(id))!;
        expect(suspended.status, WorkflowStatus.suspended);
        expect(
          await app.resumeDueRuns(
            suspended.resumeAt!.add(const Duration(seconds: 1)),
          ),
          [id],
        );
        await app.executeRun(id);
        final completed = (await app.getRun(id))!;
        expect(completed.status, WorkflowStatus.completed);
        final host = await WorkflowHost.attach(app: app, workflows: [workflow]);
        addTearDown(host.close);
        expect(
          await (await host.observe(workflow, id)).result,
          eventDeadline ? 'deadline' : 'awake',
        );
      },
    );
  }

  test('sleep suspends once and preserves completed checkpoints', () async {
    var before = 0;
    var after = 0;
    final workflow = HostedWorkflow<String, String>(
      name: 'host.sleep',
      run: (context, input) async {
        await context.step('before', () {
          before++;
          return input;
        });
        await context.sleep('pause', const Duration(milliseconds: 1));
        return context.step('after', () {
          after++;
          return input;
        });
      },
    );
    final host = await WorkflowHost.inMemory(workflows: [workflow]);
    addTearDown(host.close);
    expect(
      await host.execute(workflow, 'done').timeout(const Duration(seconds: 5)),
      'done',
    );
    expect(before, 1);
    expect(after, 1);
  });

  for (final name in <String?>['Ada', null]) {
    test('map transport decodes nullable DTO $name across replay', () async {
      final approval = WorkflowEventRef<_Approval?>(
        topic: 'approval.$name',
        codec: PayloadCodec<_Approval?>(
          encode: (value) => {'name': value?.name},
          decode: (payload) {
            final value = (payload! as Map)['name'] as String?;
            return value == null ? null : _Approval(value);
          },
        ),
      );
      final finish = WorkflowEventRef<Map<String, Object?>>(
        topic: 'finish.$name',
      );
      final workflow = HostedWorkflow<String, String?>(
        name: 'host.dto.$name',
        run: (context, _) async {
          final value = await context.awaitEvent('approval', approval);
          // This forces the preceding decoded event checkpoint to replay.
          await context.awaitEvent('finish', finish);
          return value?.name;
        },
      );
      final host = await WorkflowHost.inMemory(workflows: [workflow]);
      addTearDown(host.close);
      final run = await host.submit(workflow, 'input');
      await _waitingAt(run, 'approval');
      await host.emitEvent(approval, name == null ? null : _Approval(name));
      await _waitingAt(run, 'finish');
      await host.emitEvent(finish, <String, Object?>{});
      expect(
        await run.result.timeout(const Duration(seconds: 5)),
        name,
      );
    });
  }

  test('event payload control-like keys never signal a timeout', () async {
    const event = WorkflowEventRef<Map<String, Object?>>(topic: 'lookalike');
    const payload = <String, Object?>{
      'type': 'event',
      'step': 'event',
      'suspendedAt': '2024-01-01T00:00:00Z',
      'resumeReason': 'eventDeadline',
      'timedOut': true,
      'value': null,
    };
    final workflow = HostedWorkflow<String, Map<String, Object?>>(
      name: 'host.lookalike',
      run: (context, _) => context.awaitEvent('event', event),
    );
    final host = await WorkflowHost.inMemory(workflows: [workflow]);
    addTearDown(host.close);
    final run = await host.submit(workflow, 'input');
    await _waitingAt(run, 'event');
    await host.emitEvent(event, payload);
    expect(await run.result.timeout(const Duration(seconds: 5)), payload);
  });

  test(
    'caught event deadline is checkpointed and replays as timeout',
    () async {
      var catches = 0;
      const event = WorkflowEventRef<Map<String, Object?>>(topic: 'never');
      const finish = WorkflowEventRef<Map<String, Object?>>(
        topic: 'after-timeout',
      );
      final deadline = DateTime.now().toUtc();
      final workflow = HostedWorkflow<String, String>(
        name: 'host.deadline',
        run: (context, _) async {
          try {
            await context.awaitEvent('deadline', event, deadline: deadline);
            throw StateError('Expired wait unexpectedly returned a payload.');
          } on TimeoutException {
            catches++;
          }
          await context.awaitEvent('finish', finish);
          return 'handled';
        },
      );
      final host = await WorkflowHost.inMemory(workflows: [workflow]);
      addTearDown(host.close);
      final run = await host.submit(workflow, 'input');
      await _waitingAt(run, 'finish');
      expect(catches, 1);
      await host.emitEvent(finish, <String, Object?>{});
      expect(
        await run.result.timeout(const Duration(seconds: 5)),
        'handled',
      );
      expect(catches, 2);
    },
  );
}

Future<void> _waitingAt<R>(HostedRun<R> run, String step) async {
  await run
      .watch()
      .firstWhere(
        (view) =>
            view.status == WorkflowStatus.suspended &&
            view.suspensionData?['step'] == step,
      )
      .timeout(const Duration(seconds: 5));
}

class _Approval {
  const _Approval(this.name);
  final String name;
}
