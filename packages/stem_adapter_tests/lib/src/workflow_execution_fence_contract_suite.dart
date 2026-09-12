import 'package:stem/stem.dart';
import 'package:stem_adapter_tests/src/workflow_store_contract_suite.dart';
import 'package:test/test.dart';

/// Tests the optional execution-fencing capability against an actual store.
///
/// Invoke this suite only for adapters advertising [FencedWorkflowStore].
/// These checks use the supplied clock and never sleep for lease expiry.
void runWorkflowExecutionFenceContractTests({
  required String adapterName,
  required WorkflowStoreContractFactory factory,
}) {
  group('$adapterName workflow execution fences', () {
    WorkflowStore? store;
    late FencedWorkflowStore fenced;
    late FakeWorkflowClock clock;

    setUp(() async {
      clock = FakeWorkflowClock(DateTime.utc(2024));
      store = await factory.create(clock);
      expect(store, isA<FencedWorkflowStore>());
      fenced = store! as FencedWorkflowStore;
    });
    tearDown(() async {
      if (store != null) await factory.dispose?.call(store!);
    });

    Future<String> create() =>
        store!.createRun(workflow: 'fenced.contract', params: const {});

    Future<TerminalFailureResult> fail(
      String id,
      String executionId, {
      bool terminal = true,
    }) => fenced.markFailedForExecution(
      id,
      executionId: executionId,
      error: StateError('failure'),
      stack: StackTrace.empty,
      terminal: terminal,
    );

    test('concurrent same-owner claims have exactly one winner', () async {
      final id = await create();
      final claims = await Future.wait([
        fenced.claimRunExecution(id, ownerId: 'same'),
        fenced.claimRunExecution(id, ownerId: 'same'),
      ]);
      final claim = claims.whereType<WorkflowExecutionClaim>().single;
      expect((await store!.get(id))!.executionId, claim.executionId);
      expect(claim.runId, id);
      expect(claim.executionId, isNotEmpty);
    });

    test('released token cannot mutate a new same-owner claim', () async {
      final id = await create();
      final first = (await fenced.claimRunExecution(id, ownerId: 'same'))!;
      await store!.markRunning(id);
      expect((await store!.get(id))!.executionId, first.executionId);
      await fenced.releaseRunExecution(id, executionId: first.executionId);
      expect((await store!.get(id))!.executionId, first.executionId);
      final second = (await fenced.claimRunExecution(id, ownerId: 'same'))!;
      expect(second.executionId, isNot(first.executionId));
      expect(
        await fenced.renewRunExecution(id, executionId: first.executionId),
        isFalse,
      );
      await fenced.releaseRunExecution(id, executionId: first.executionId);
      expect((await store!.get(id))!.ownerId, 'same');
      expect(
        await fail(id, first.executionId),
        TerminalFailureResult.superseded,
      );
      await store!.markCompleted(id, 'newer result');
      expect(
        await fail(id, second.executionId),
        TerminalFailureResult.superseded,
      );
      expect((await store!.get(id))!.result, 'newer result');
    });

    test(
      'expired tokens cannot renew and a new claim rotates identity',
      () async {
        final id = await create();
        final first = (await fenced.claimRunExecution(
          id,
          ownerId: 'same',
          leaseDuration: const Duration(seconds: 1),
        ))!;
        clock.advance(const Duration(seconds: 2));
        expect(
          await fenced.renewRunExecution(id, executionId: first.executionId),
          isFalse,
        );
        final second = (await fenced.claimRunExecution(id, ownerId: 'same'))!;
        expect(second.executionId, isNot(first.executionId));
        expect(
          await fail(id, first.executionId),
          TerminalFailureResult.superseded,
        );
      },
    );

    test(
      'legacy operations cannot renew or release a tokenized lease',
      () async {
        final id = await create();
        final claim = (await fenced.claimRunExecution(id, ownerId: 'same'))!;
        expect(await store!.claimRun(id, ownerId: 'same'), isFalse);
        expect(await store!.renewRunLease(id, ownerId: 'same'), isFalse);
        await store!.releaseRun(id, ownerId: 'same');
        expect((await store!.get(id))!.ownerId, 'same');
        await fenced.releaseRunExecution(id, executionId: claim.executionId);
        expect(await store!.claimRun(id, ownerId: 'legacy'), isTrue);
        expect((await store!.get(id))!.executionId, isNull);
        expect(
          await fail(id, claim.executionId),
          TerminalFailureResult.superseded,
        );
      },
    );

    test(
      'attempt errors remain retryable, terminal application is idempotent',
      () async {
        final id = await create();
        final claim = (await fenced.claimRunExecution(id, ownerId: 'owner'))!;
        expect(
          await fail(id, claim.executionId, terminal: false),
          TerminalFailureResult.applied,
        );
        final retryable = (await store!.get(id))!;
        expect(retryable.status, WorkflowStatus.running);
        expect(retryable.ownerId, 'owner');
        expect(retryable.executionId, claim.executionId);
        expect(retryable.lastError?['error'], contains('failure'));
        expect(
          await fail(id, claim.executionId),
          TerminalFailureResult.applied,
        );
        expect(
          await fail(id, claim.executionId),
          TerminalFailureResult.alreadyFailedForExecution,
        );
        final failed = (await store!.get(id))!;
        expect(failed.status, WorkflowStatus.failed);
        expect(failed.ownerId, isNull);
        expect(failed.leaseExpiresAt, isNull);
        expect(failed.executionId, claim.executionId);
      },
    );

    test('resume and rewind invalidate prior execution identities', () async {
      final id = await create();
      await store!.saveStep(id, 'checkpoint', 1);
      final first = (await fenced.claimRunExecution(id, ownerId: 'owner'))!;
      await store!.markResumed(id);
      expect((await store!.get(id))!.executionId, isNull);
      expect((await store!.get(id))!.ownerId, isNull);
      expect(
        await fail(id, first.executionId),
        TerminalFailureResult.superseded,
      );
      final second = (await fenced.claimRunExecution(id, ownerId: 'owner'))!;
      await store!.rewindToStep(id, 'checkpoint');
      final rewound = (await store!.get(id))!;
      expect(rewound.executionId, isNull);
      expect(rewound.ownerId, isNull);
      expect(rewound.leaseExpiresAt, isNull);
      expect(
        await fail(id, second.executionId),
        TerminalFailureResult.superseded,
      );
    });

    test(
      'cancellation cannot be overwritten by failure finalization',
      () async {
        final id = await create();
        final claim = (await fenced.claimRunExecution(id, ownerId: 'owner'))!;
        await store!.cancel(id);
        expect(
          await fail(id, claim.executionId),
          TerminalFailureResult.superseded,
        );
        expect((await store!.get(id))!.status, WorkflowStatus.cancelled);
      },
    );

    test('terminal failure removes pending watchers and due work', () async {
      final id = await create();
      final claim = (await fenced.claimRunExecution(id, ownerId: 'owner'))!;
      await store!.registerWatcher(
        id,
        'wait',
        'fenced.topic',
        deadline: clock.now().add(const Duration(seconds: 1)),
      );
      expect(await fail(id, claim.executionId), TerminalFailureResult.applied);
      expect(await store!.listWatchers('fenced.topic'), isEmpty);
      clock.advance(const Duration(seconds: 2));
      expect(await store!.dueRuns(clock.now()), isNot(contains(id)));
      expect((await store!.get(id))!.status, WorkflowStatus.failed);
    });
  });
}
