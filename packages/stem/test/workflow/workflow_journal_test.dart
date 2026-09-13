import 'package:stem/memory.dart';
import 'package:stem/src/workflow/runtime/workflow_journal_controller.dart';
import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  late FakeWorkflowClock clock;
  late InMemoryWorkflowStore store;
  late WorkflowJournalController journal;
  late String runId;
  late String executionId;

  setUp(() async {
    clock = FakeWorkflowClock(DateTime.utc(2024));
    store = InMemoryWorkflowStore(clock: clock);
    journal = WorkflowJournalController(store, clock);
    runId = await store.createRun(workflow: 'journal', params: const {});
    executionId = (await store.claimRunExecution(
      runId,
      ownerId: 'owner',
    ))!.executionId;
  });

  Future<void> nextExecution() async {
    await store.releaseRunExecution(runId, executionId: executionId);
    executionId = (await store.claimRunExecution(
      runId,
      ownerId: 'owner',
    ))!.executionId;
  }

  test('retry ETA and exhaustion survive fresh execution claims', () async {
    const policy = WorkflowRetryPolicy(
      maxAttempts: 2,
      delay: Duration(seconds: 2),
    );
    final first = await journal.claimStep(runId, 'step', executionId, policy);
    expect(first.acquired, isTrue);
    expect(first.attempts, 1);
    final waiting = await journal.fail(
      first,
      StateError('fail'),
      StackTrace.empty,
    );
    expect(waiting.readyAt, clock.now().add(const Duration(seconds: 2)));
    await nextExecution();
    final early = await journal.claimStep(runId, 'step', executionId, policy);
    expect(early.acquired, isFalse);
    expect(early.state, 'waiting');
    clock.advance(const Duration(seconds: 2));
    final second = await journal.claimStep(runId, 'step', executionId, policy);
    expect(second.attempts, 2);
    expect(second.acquired, isTrue);
    expect(
      (await journal.fail(second, StateError('last'), StackTrace.empty)).state,
      'exhausted',
    );
    await nextExecution();
    final exhausted = await journal.claimStep(
      runId,
      'step',
      executionId,
      policy,
    );
    expect(exhausted.state, 'exhausted');
    expect(exhausted.attempts, 2);
    expect(exhausted.acquired, isFalse);
  });

  test(
    'abandoned attempt consumes budget and stale completion is rejected',
    () async {
      const policy = WorkflowRetryPolicy(maxAttempts: 2);
      final old = await journal.claimStep(runId, 'step', executionId, policy);
      clock.advance(const Duration(seconds: 31));
      executionId = (await store.claimRunExecution(
        runId,
        ownerId: 'replacement',
      ))!.executionId;
      final replacement = await journal.claimStep(
        runId,
        'step',
        executionId,
        policy,
      );
      expect(replacement.attempts, 2);
      await expectLater(
        journal.completeStep(old, 'stale'),
        throwsA(isA<WorkflowJournalConflict>()),
      );
      await journal.completeStep(replacement, const {'value': 'saved'});
      expect(await store.readStep<Object?>(runId, 'step'), {'value': 'saved'});
      final cached = await journal.claimStep(
        runId,
        'step',
        executionId,
        policy,
      );
      expect(cached.state, 'completed');
      expect(cached.acquired, isFalse);
      expect((await store.listSteps(runId)).length, 1);
    },
  );

  Future<void> register(String name, {int maxAttempts = 2}) async {
    final attempt = await journal.claimStep(
      runId,
      name,
      executionId,
      const WorkflowRetryPolicy(),
    );
    await journal.completeStep(
      attempt,
      {'value': name},
      compensation: WorkflowCompensationRegistration(
        handler: 'undo',
        input: name,
        retryPolicy: WorkflowRetryPolicy(
          maxAttempts: maxAttempts,
          delay: const Duration(seconds: 1),
        ),
      ),
    );
  }

  Future<void> failRun() async {
    await store.markFailedForExecution(
      runId,
      executionId: executionId,
      error: StateError('terminal'),
      stack: StackTrace.empty,
    );
  }

  test(
    'cleanup is reverse ordered, ETA-aware, and does not repeat success',
    () async {
      await register('a');
      await register('b');
      await failRun();
      final last = (await journal.claimCompensation(runId, executionId))!;
      expect(last.entry.name, 'b');
      await journal.fail(last, StateError('cleanup'), StackTrace.empty);
      final waiting = (await journal.claimCompensation(runId, executionId))!;
      expect(waiting.entry.name, 'b');
      expect(waiting.acquired, isFalse);
      clock.advance(const Duration(seconds: 1));
      final retry = (await journal.claimCompensation(runId, executionId))!;
      expect(retry.attempts, 2);
      await journal.completeCompensation(retry);
      final first = (await journal.claimCompensation(runId, executionId))!;
      expect(first.entry.name, 'a');
      await journal.completeCompensation(first);
      expect(await journal.claimCompensation(runId, executionId), isNull);
      await expectLater(
        journal.completeCompensation(last),
        throwsA(isA<WorkflowJournalConflict>()),
      );
    },
  );

  test(
    'cleanup leases expire and administrative retry preserves attempt counts',
    () async {
      await register('a', maxAttempts: 1);
      await failRun();
      final first = (await journal.claimCompensation(
        runId,
        executionId,
        leaseDuration: const Duration(seconds: 1),
      ))!;
      expect(
        (await journal.claimCompensation(runId, executionId))!.acquired,
        isFalse,
      );
      clock.advance(const Duration(seconds: 2));
      expect(
        (await journal.claimCompensation(runId, executionId))!.state,
        'exhausted',
      );
      await journal.extendCompensationBudget(runId, 'a', executionId, 1);
      final second = (await journal.claimCompensation(runId, executionId))!;
      expect(second.attempts, 2);
      expect(second.token, isNot(first.token));
      await expectLater(
        journal.completeCompensation(first),
        throwsA(isA<WorkflowJournalConflict>()),
      );
      await journal.completeCompensation(second);
    },
  );

  test('cancellation and rewind fence cleanup claims', () async {
    await register('a');
    await store.cancel(runId);
    await expectLater(
      journal.claimCompensation(runId, executionId),
      throwsA(isA<WorkflowJournalConflict>()),
    );
    await store.rewindToStep(runId, 'a');
    expect(await store.listCompensations(runId), isEmpty);
  });

  test(
    'retry policies reject invalid values and retain precise bounded delays',
    () {
      const policy = WorkflowRetryPolicy(
        maxAttempts: 4,
        delay: Duration(microseconds: 125),
        multiplier: 2,
        maxDelay: Duration(microseconds: 500),
      );
      expect(WorkflowRetryPolicy.fromJson(policy.toJson()).delay, policy.delay);
      expect(policy.delayAfter(1).inMicroseconds, 125);
      expect(policy.delayAfter(99).inMicroseconds, 500);
      expect(
        () => const WorkflowRetryPolicy(maxAttempts: 0).validate(),
        throwsArgumentError,
      );
      expect(
        () => WorkflowRetryPolicy.fromJson({'maxAttempts': 1.5}),
        throwsFormatException,
      );
    },
  );
}
