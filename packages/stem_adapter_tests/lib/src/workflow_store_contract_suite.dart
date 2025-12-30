import 'dart:async';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

class WorkflowStoreContractFactory {
  const WorkflowStoreContractFactory({required this.create, this.dispose});

  final Future<WorkflowStore> Function(FakeWorkflowClock clock) create;
  final FutureOr<void> Function(WorkflowStore store)? dispose;
}

void runWorkflowStoreContractTests({
  required String adapterName,
  required WorkflowStoreContractFactory factory,
}) {
  group('$adapterName workflow store contract', () {
    WorkflowStore? store;
    late FakeWorkflowClock clock;

    setUp(() async {
      clock = FakeWorkflowClock(DateTime.utc(2024, 1, 1));
      store = await factory.create(clock);
    });

    tearDown(() async {
      final instance = store;
      if (instance != null && factory.dispose != null) {
        await factory.dispose!(instance);
      }
      store = null;
    });

    test('createRun persists metadata and cursor defaults to zero', () async {
      final current = store!;
      final runId = await current.createRun(
        workflow: 'contract.workflow',
        params: const {'user': 1},
      );

      final state = await current.get(runId);
      expect(state, isNotNull);
      expect(state!.workflow, 'contract.workflow');
      expect(state.status, WorkflowStatus.running);
      expect(state.cursor, 0);
      expect(state.params['user'], 1);
    });

    test('saveStep/readStep/rewind maintain checkpoints', () async {
      final current = store!;
      final runId = await current.createRun(
        workflow: 'contract.workflow',
        params: const {},
      );

      await current.saveStep(runId, 'step-a', const {'value': 1});
      await current.saveStep(runId, 'step-b', 2);
      await current.saveStep(runId, 'step-c', 'done');

      expect(await current.readStep<Map<String, Object?>>(runId, 'step-a'), {
        'value': 1,
      });
      expect(await current.readStep<int>(runId, 'step-b'), 2);

      await current.rewindToStep(runId, 'step-b');

      expect(await current.readStep(runId, 'step-b'), isNull);
      expect(await current.readStep(runId, 'step-c'), isNull);
      expect(await current.readStep<Map<String, Object?>>(runId, 'step-a'), {
        'value': 1,
      });

      final state = await current.get(runId);
      expect(state?.cursor, 1);
    });

    test('saveStep refreshes updatedAt heartbeat', () async {
      final current = store!;
      final runId = await current.createRun(
        workflow: 'contract.workflow',
        params: const {},
      );

      final initial = await current.get(runId);
      expect(initial?.updatedAt, isNotNull);

      // Ensure the timestamp resolution has time to advance on fast systems.
      clock.advance(const Duration(milliseconds: 2));

      await current.saveStep(runId, 'heartbeat', true);
      final after = await current.get(runId);
      expect(after?.updatedAt, isNotNull);
      expect(after!.updatedAt!.isAfter(initial!.updatedAt!), isTrue);
    });

    test(
      'autoVersion checkpoints persist and rewind with iteration metadata',
      () async {
        final current = store!;
        final runId = await current.createRun(
          workflow: 'contract.workflow',
          params: const {},
        );

        await current.saveStep(runId, 'repeat#0', 'first');
        await current.saveStep(runId, 'repeat#1', 'second');
        await current.saveStep(runId, 'tail', 'done');

        var state = await current.get(runId);
        expect(state?.cursor, 2); // repeat + tail

        expect(await current.readStep(runId, 'repeat#0'), 'first');
        expect(await current.readStep(runId, 'repeat#1'), 'second');

        await current.rewindToStep(runId, 'repeat');

        expect(await current.readStep(runId, 'repeat#0'), isNull);
        expect(await current.readStep(runId, 'repeat#1'), isNull);
        expect(await current.readStep(runId, 'tail'), isNull);

        state = await current.get(runId);
        expect(state?.cursor, 0);
        expect(state?.status, WorkflowStatus.suspended);
        expect(state?.suspensionData?['step'], 'repeat');
        expect(state?.suspensionData?['iteration'], 0);
        expect(state?.suspensionData?['iterationStep'], 'repeat');
      },
    );

    test('listRuns reports logical cursor for versioned checkpoints', () async {
      final current = store!;
      final runId = await current.createRun(
        workflow: 'contract.workflow',
        params: const {},
      );

      await current.saveStep(runId, 'repeat#0', 'first');
      await current.saveStep(runId, 'repeat#1', 'second');
      await current.saveStep(runId, 'tail', 'done');

      final active = await current.listRuns(
        workflow: 'contract.workflow',
        limit: 5,
      );
      expect(active, isNotEmpty);
      final run = active.firstWhere((state) => state.id == runId);
      expect(run.cursor, 2); // repeat + tail

      await current.rewindToStep(runId, 'repeat');
      final rewound = await current.listRuns(
        workflow: 'contract.workflow',
        limit: 5,
      );
      final updated = rewound.firstWhere((state) => state.id == runId);
      expect(updated.cursor, 0);
      expect(updated.status, WorkflowStatus.suspended);
      expect(updated.suspensionData?['iteration'], 0);
    });

    test('suspendUntil/dueRuns/markResumed workflow lifecycle', () async {
      final current = store!;
      final runId = await current.createRun(
        workflow: 'contract.workflow',
        params: const {},
      );

      final resumeAt = clock.now().subtract(const Duration(seconds: 1));
      await current.suspendUntil(
        runId,
        'step-a',
        resumeAt,
        data: const {'reason': 'delay'},
      );

      final suspended = await current.get(runId);
      expect(suspended?.suspensionData?['resumeAt'], isNotNull);

      final due = await current.dueRuns(clock.now());
      expect(due, contains(runId));

      // Once selected, the run should not appear again until resuspended.
      final second = await current.dueRuns(clock.now());
      expect(second, isEmpty);

      await current.markResumed(runId);
      final state = await current.get(runId);
      expect(state?.status, WorkflowStatus.running);
      expect(state?.waitTopic, isNull);
    });

    test('dueRuns honors limit and leaves remaining runs due', () async {
      final current = store!;
      final resumeAt = clock.now().subtract(const Duration(seconds: 1));
      final runIds = <String>[];

      for (var i = 0; i < 3; i++) {
        final runId = await current.createRun(
          workflow: 'contract.workflow',
          params: const {'batch': true},
        );
        await current.suspendUntil(
          runId,
          'step-$i',
          resumeAt,
          data: {'index': i},
        );
        runIds.add(runId);
      }

      final firstBatch = await current.dueRuns(clock.now(), limit: 2);
      expect(firstBatch.length, 2);

      final secondBatch = await current.dueRuns(clock.now(), limit: 2);
      expect(secondBatch.length, 1);

      final combined = {...firstBatch, ...secondBatch}.toSet();
      expect(combined, runIds.toSet());
    });

    test('suspendOnTopic/runsWaitingOn/cancel workflow lifecycle', () async {
      final current = store!;
      final runId = await current.createRun(
        workflow: 'contract.workflow',
        params: const {},
      );

      await current.suspendOnTopic(
        runId,
        'step-b',
        'user.updated',
        deadline: clock.now().add(const Duration(hours: 1)),
        data: const {'topic': true},
      );

      final waiting = await current.runsWaitingOn('user.updated');
      expect(waiting, contains(runId));

      await current.cancel(runId);
      final state = await current.get(runId);
      expect(state?.status, WorkflowStatus.cancelled);
      expect(state?.waitTopic, isNull);
    });

    test('runsWaitingOn returns all workflows suspended on a topic', () async {
      final current = store!;
      final runIds = <String>[];
      for (var i = 0; i < 3; i++) {
        final runId = await current.createRun(
          workflow: 'contract.workflow.$i',
          params: const {},
        );
        await current.suspendOnTopic(
          runId,
          'group-step',
          'group.topic',
          data: {'index': i},
        );
        runIds.add(runId);
      }

      final waiting = await current.runsWaitingOn('group.topic');
      expect(waiting.toSet(), runIds.toSet());

      for (final runId in runIds) {
        await current.markResumed(runId, data: {'payload': 'resume-$runId'});
      }

      final after = await current.runsWaitingOn('group.topic');
      expect(after, isEmpty);

      for (final runId in runIds) {
        final state = await current.get(runId);
        expect(state?.status, WorkflowStatus.running);
        expect(state?.suspensionData?['payload'], 'resume-$runId');
        expect(state?.waitTopic, isNull);
      }
    });

    test('registerWatcher resolves payload exactly once', () async {
      final current = store!;
      final runId = await current.createRun(
        workflow: 'contract.workflow',
        params: const {},
      );

      await current.registerWatcher(
        runId,
        'event-step',
        'contract.topic',
        data: const <String, Object?>{
          'step': 'event-step',
          'iteration': 0,
          'iterationStep': 'event-step',
        },
      );

      final waiting = await current.runsWaitingOn('contract.topic');
      expect(waiting, contains(runId));

      final watchers = await current.listWatchers('contract.topic');
      expect(watchers, isNotEmpty);
      expect(watchers.first.runId, runId);
      expect(watchers.first.stepName, 'event-step');

      final resolutions = await current.resolveWatchers(
        'contract.topic',
        const <String, Object?>{'value': 42},
      );
      expect(resolutions, hasLength(1));
      final resolution = resolutions.first;
      expect(resolution.runId, runId);
      expect(resolution.stepName, 'event-step');
      expect(resolution.topic, 'contract.topic');
      expect(resolution.resumeData['payload'], {'value': 42});
      expect(resolution.resumeData['topic'], 'contract.topic');

      expect(await current.listWatchers('contract.topic'), isEmpty);

      final after = await current.runsWaitingOn('contract.topic');
      expect(after, isEmpty);

      final state = await current.get(runId);
      expect(state, isNotNull);
      expect(state!.suspensionData?['payload'], {'value': 42});
    });

    test('listWatchers exposes metadata including deadlines', () async {
      final current = store!;
      final runId = await current.createRun(
        workflow: 'contract.workflow',
        params: const {},
      );
      final deadline = clock.now().add(const Duration(minutes: 5));

      await current.registerWatcher(
        runId,
        'inspect-step',
        'contract.inspect',
        deadline: deadline,
        data: const <String, Object?>{'note': 'contract-test'},
      );

      final watchers = await current.listWatchers('contract.inspect');
      expect(watchers, hasLength(1));
      final watcher = watchers.first;
      expect(watcher.runId, runId);
      expect(watcher.stepName, 'inspect-step');
      expect(watcher.topic, 'contract.inspect');
      expect(watcher.data['note'], 'contract-test');
      expect(watcher.deadline, isNotNull);
      if (watcher.deadline != null) {
        final delta = watcher.deadline!.difference(deadline).abs();
        expect(delta.inSeconds < 5, isTrue);
      }
    });

    test('markCompleted stores result and clears suspension data', () async {
      final current = store!;
      final runId = await current.createRun(
        workflow: 'contract.workflow',
        params: const {},
      );

      await current.markCompleted(runId, const {'output': 'ok'});

      final state = await current.get(runId);
      expect(state?.status, WorkflowStatus.completed);
      expect(state?.result, {'output': 'ok'});
      expect(state?.suspensionData, isEmpty);
    });

    test('markFailed records last error metadata', () async {
      final current = store!;
      final runId = await current.createRun(
        workflow: 'contract.workflow',
        params: const {},
      );

      await current.markFailed(
        runId,
        StateError('contract failure'),
        StackTrace.current,
      );

      final state = await current.get(runId);
      expect(state?.status, WorkflowStatus.running);
      expect(state?.lastError, isNotEmpty);
      expect(state?.lastError?['error'], contains('contract failure'));

      await current.markFailed(
        runId,
        ArgumentError('boom'),
        StackTrace.current,
        terminal: true,
      );

      final failed = await current.get(runId);
      expect(failed?.status, WorkflowStatus.failed);
    });

    test('listRuns supports workflow/status filters', () async {
      final current = store!;
      final first = await current.createRun(
        workflow: 'contract.a',
        params: const {},
      );
      final second = await current.createRun(
        workflow: 'contract.b',
        params: const {},
      );
      await current.markCompleted(first, null);

      final all = await current.listRuns(limit: 10);
      final ids = all.map((state) => state.id).toList();
      expect(ids, containsAll([first, second]));

      final onlyA = await current.listRuns(workflow: 'contract.a', limit: 10);
      expect(onlyA, hasLength(1));
      expect(onlyA.first.workflow, 'contract.a');
      expect(onlyA.first.status, WorkflowStatus.completed);

      final completed = await current.listRuns(
        status: WorkflowStatus.completed,
        limit: 10,
      );
      expect(completed.map((s) => s.id), contains(first));
    });

    test('listSteps returns checkpoints in execution order', () async {
      final current = store!;
      final runId = await current.createRun(
        workflow: 'contract.workflow',
        params: const {},
      );
      await current.saveStep(runId, 'step-a', 1);
      await current.saveStep(runId, 'step-b', 2);
      await current.saveStep(runId, 'step-c', 3);

      final steps = await current.listSteps(runId);
      expect(steps.map((s) => s.name), ['step-a', 'step-b', 'step-c']);
      expect(steps.map((s) => s.value), [1, 2, 3]);
    });

    test('listSteps includes versioned checkpoints in order', () async {
      final current = store!;
      final runId = await current.createRun(
        workflow: 'contract.workflow',
        params: const {},
      );
      await current.saveStep(runId, 'repeat#0', 'first');
      await current.saveStep(runId, 'repeat#1', 'second');
      await current.saveStep(runId, 'tail', 'done');

      final steps = await current.listSteps(runId);
      expect(steps.map((s) => s.name), ['repeat#0', 'repeat#1', 'tail']);
    });

    test('createRun persists cancellation policy metadata', () async {
      final current = store!;
      final policy = const WorkflowCancellationPolicy(
        maxRunDuration: Duration(minutes: 5),
        maxSuspendDuration: Duration(minutes: 1),
      );
      final runId = await current.createRun(
        workflow: 'policy.workflow',
        params: const {},
        cancellationPolicy: policy,
      );

      final state = await current.get(runId);
      expect(state, isNotNull);
      expect(state!.cancellationPolicy?.maxRunDuration, policy.maxRunDuration);
      expect(
        state.cancellationPolicy?.maxSuspendDuration,
        policy.maxSuspendDuration,
      );
      expect(state.createdAt, isNotNull);
    });

    test('cancel persists cancellation data reason', () async {
      final current = store!;
      final runId = await current.createRun(
        workflow: 'cancel.workflow',
        params: const {},
      );

      await current.cancel(runId, reason: 'maxRunDuration');

      final state = await current.get(runId);
      expect(state?.status, WorkflowStatus.cancelled);
      expect(state?.cancellationData?['reason'], 'maxRunDuration');
    });
  });
}
