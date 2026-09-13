import 'dart:async';

import 'package:stem/stem.dart';
import 'package:stem_adapter_tests/src/workflow_store_contract_suite.dart';
import 'package:test/test.dart';

/// Runs the optional atomic terminal-transition contract.
///
/// Adapters are expected to implement [WorkflowTerminalStore] when this suite
/// is registered. All time-sensitive assertions use the supplied fake clock.
void runWorkflowTerminalContractTests({
  required String adapterName,
  required WorkflowStoreContractFactory factory,
}) {
  group('$adapterName workflow terminal transitions', () {
    WorkflowStore? store;
    late WorkflowTerminalStore terminal;
    late FakeWorkflowClock clock;

    setUp(() async {
      clock = FakeWorkflowClock(DateTime.utc(2024));
      store = await factory.create(clock);
      expect(store, isA<WorkflowTerminalStore>());
      terminal = store! as WorkflowTerminalStore;
    });

    tearDown(() async {
      if (store != null) await factory.dispose?.call(store!);
      store = null;
    });

    Future<String> create() => store!.createRun(
      workflow: 'terminal.contract',
      params: const {},
      ttl: const Duration(hours: 1),
    );

    test('missing runs return false', () async {
      expect(await terminal.completeIfActive('missing', 'result'), isFalse);
      expect(
        await terminal.cancelIfActive('missing', reason: 'missing'),
        isFalse,
      );
    });

    test('completion wins and cannot be cancelled or overwritten', () async {
      final id = await create();
      await store!.claimRun(id, ownerId: 'worker');
      await store!.suspendOnTopic(
        id,
        'wait',
        'terminal.topic',
        deadline: clock.now().add(const Duration(minutes: 1)),
        data: const {'held': true},
      );
      expect(await terminal.completeIfActive(id, const {'answer': 42}), isTrue);
      expect(
        await terminal.completeIfActive(id, 'replacement'),
        isFalse,
      );
      expect(await terminal.cancelIfActive(id, reason: 'too late'), isFalse);

      final state = (await store!.get(id))!;
      expect(state.status, WorkflowStatus.completed);
      expect(state.result, {'answer': 42});
      expect(state.cancellationData, isNull);
      expect(state.waitTopic, isNull);
      expect(state.resumeAt, isNull);
      expect(state.suspensionData, isEmpty);
      expect(state.ownerId, isNull);
      expect(state.leaseExpiresAt, isNull);
      expect(
        await store!.dueRuns(clock.now().add(const Duration(hours: 2))),
        isEmpty,
      );
      expect(await store!.runsWaitingOn('terminal.topic'), isEmpty);
      expect(await store!.listWatchers('terminal.topic'), isEmpty);
    });

    test('cancellation wins and cannot be completed or overwritten', () async {
      final id = await create();
      await store!.claimRun(id, ownerId: 'worker');
      await store!.registerWatcher(
        id,
        'wait',
        'terminal.cancel.topic',
        deadline: clock.now().add(const Duration(minutes: 1)),
        data: const {'held': true},
      );
      final cancelledAt = clock.now();

      expect(
        await terminal.cancelIfActive(id, reason: 'operator requested'),
        isTrue,
      );
      expect(await terminal.cancelIfActive(id, reason: 'replacement'), isFalse);
      expect(await terminal.completeIfActive(id, 'too late'), isFalse);

      final state = (await store!.get(id))!;
      expect(state.status, WorkflowStatus.cancelled);
      expect(state.result, isNull);
      expect(state.cancellationData?['reason'], 'operator requested');
      expect(
        state.cancellationData?['cancelledAt'],
        cancelledAt.toIso8601String(),
      );
      expect(state.waitTopic, isNull);
      expect(state.resumeAt, isNull);
      expect(state.suspensionData, isEmpty);
      expect(state.ownerId, isNull);
      expect(state.leaseExpiresAt, isNull);
      expect(
        await store!.dueRuns(clock.now().add(const Duration(hours: 2))),
        isEmpty,
      );
      expect(await store!.runsWaitingOn('terminal.cancel.topic'), isEmpty);
      expect(await store!.listWatchers('terminal.cancel.topic'), isEmpty);
    });

    test(
      'concurrent completion and cancellation have exactly one winner',
      () async {
        final id = await create();
        final outcomes = await Future.wait([
          terminal.completeIfActive(id, 'completed'),
          terminal.cancelIfActive(id, reason: 'cancelled'),
        ]);

        expect(outcomes.where((won) => won).length, 1);
        final state = (await store!.get(id))!;
        expect(
          state.status,
          anyOf(WorkflowStatus.completed, WorkflowStatus.cancelled),
        );
        if (state.status == WorkflowStatus.completed) {
          expect(state.result, 'completed');
          expect(state.cancellationData, isNull);
        } else {
          expect(state.result, isNull);
          expect(state.cancellationData?['reason'], 'cancelled');
        }
      },
    );

    for (final terminalStatus in <WorkflowStatus>[
      WorkflowStatus.completed,
      WorkflowStatus.cancelled,
      WorkflowStatus.failed,
    ]) {
      test('ordinary mutations cannot resurrect $terminalStatus or add '
          'wait state', () async {
        final id = await create();
        await store!.markFailed(id, StateError('original'), StackTrace.empty);
        if (terminalStatus == WorkflowStatus.completed) {
          await terminal.completeIfActive(id, 'preserved');
        } else if (terminalStatus == WorkflowStatus.cancelled) {
          await terminal.cancelIfActive(id, reason: 'preserved');
        } else {
          await store!.markFailed(
            id,
            StateError('preserved failure'),
            StackTrace.empty,
            terminal: true,
          );
        }
        final before = (await store!.get(id))!;
        final errorBefore = before.lastError == null
            ? null
            : Map<String, Object?>.of(before.lastError!);
        clock.advance(const Duration(seconds: 1));

        await store!.markRunning(id, stepName: 'step');
        await store!.markFailed(id, StateError('retry'), StackTrace.empty);
        expect((await store!.get(id))!.lastError, errorBefore);
        await store!.markFailed(
          id,
          StateError('terminal retry'),
          StackTrace.empty,
          terminal: true,
        );
        await store!.markResumed(id, data: const {'resumed': true});
        await store!.suspendUntil(
          id,
          'sleep',
          clock.now().add(const Duration(minutes: 1)),
        );
        await store!.suspendOnTopic(id, 'topic', 'resurrection.topic');
        await store!.registerWatcher(id, 'watch', 'resurrection.topic');
        await store!.resolveWatchers('resurrection.topic', const {'value': 1});

        final state = (await store!.get(id))!;
        expect(state.status, terminalStatus);
        if (terminalStatus == WorkflowStatus.completed) {
          expect(state.result, 'preserved');
          expect(state.cancellationData, isNull);
        } else if (terminalStatus == WorkflowStatus.cancelled) {
          expect(state.cancellationData?['reason'], 'preserved');
        }
        expect(state.lastError, errorBefore);
        expect(state.updatedAt, before.updatedAt);
        expect(state.waitTopic, isNull);
        expect(state.resumeAt, isNull);
        expect(state.suspensionData, isEmpty);
        expect(state.ownerId, isNull);
        expect(state.leaseExpiresAt, isNull);
        expect(
          await store!.dueRuns(clock.now().add(const Duration(hours: 2))),
          isEmpty,
        );
        expect(await store!.runsWaitingOn('resurrection.topic'), isEmpty);
        expect(await store!.listWatchers('resurrection.topic'), isEmpty);
      });
    }
  });
}
