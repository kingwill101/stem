import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:test/test.dart';

/// Exercises fencing through two independently opened database connections.
Future<void> main() async {
  final uri =
      Platform.environment['STEM_TEST_POSTGRES_URL'] ??
      'postgres://postgres:postgres@127.0.0.1:65432/stem_test';

  PostgresWorkflowStore? first;
  PostgresWorkflowStore? second;
  final namespace = 'fence_${DateTime.now().microsecondsSinceEpoch}';
  final runId = 'concurrent-fenced-failure-$namespace';
  final classificationRunId = 'classification-fenced-failure-$namespace';
  final watcherRaceRunId = 'watcher-race-$namespace';

  setUp(() async {
    first = await PostgresWorkflowStore.connect(uri, namespace: namespace);
    second = await PostgresWorkflowStore.connect(uri, namespace: namespace);
  });

  tearDown(() async {
    await first?.close();
    await second?.close();
  });

  test('concurrent terminal failures have one applied outcome', () async {
    final store = first!;
    await store.createRun(
      workflow: 'fencing.integration',
      params: const {},
      runId: runId,
    );
    final fencedFirst = first! as FencedWorkflowStore;
    final fencedSecond = second! as FencedWorkflowStore;
    final claim = (await fencedFirst.claimRunExecution(
      runId,
      ownerId: 'fencing-test',
    ))!;

    final outcomes = await Future.wait([
      fencedFirst.markFailedForExecution(
        runId,
        executionId: claim.executionId,
        error: StateError('first'),
        stack: StackTrace.empty,
      ),
      fencedSecond.markFailedForExecution(
        runId,
        executionId: claim.executionId,
        error: StateError('second'),
        stack: StackTrace.empty,
      ),
    ]);

    expect(
      outcomes.where((result) => result == TerminalFailureResult.applied),
      [TerminalFailureResult.applied],
    );
    expect(
      outcomes.where(
        (result) => result == TerminalFailureResult.alreadyFailedForExecution,
      ),
      [TerminalFailureResult.alreadyFailedForExecution],
    );
    expect((await store.get(runId))!.status, WorkflowStatus.failed);
  });

  test(
    'classification and retryable failures use the locked transaction',
    () async {
      final store = first!;
      await store.createRun(
        workflow: 'fencing.integration',
        params: const {},
        runId: classificationRunId,
      );
      final fenced = first! as FencedWorkflowStore;

      expect(
        await fenced.markFailedForExecution(
          classificationRunId,
          executionId: 'stale-token',
          error: StateError('stale'),
          stack: StackTrace.empty,
        ),
        TerminalFailureResult.superseded,
      );
      expect(
        await fenced.markFailedForExecution(
          classificationRunId,
          executionId: 'new-token',
          error: StateError('attempt'),
          stack: StackTrace.empty,
          terminal: false,
        ),
        TerminalFailureResult.superseded,
      );

      final claim = (await fenced.claimRunExecution(
        classificationRunId,
        ownerId: 'fencing-test',
      ))!;
      expect(
        await fenced.markFailedForExecution(
          classificationRunId,
          executionId: claim.executionId,
          error: StateError('attempt'),
          stack: StackTrace.empty,
          terminal: false,
        ),
        TerminalFailureResult.applied,
      );
      final run = await store.get(classificationRunId);
      expect(run!.status, WorkflowStatus.running);
      expect(run.lastError?['error'], contains('attempt'));
    },
  );

  test(
    'a terminal failure wins over a resolver with a stale topic candidate',
    () async {
      final store = first!;
      await store.createRun(
        workflow: 'fencing.integration',
        params: const {},
        runId: watcherRaceRunId,
      );
      final claim = (await (store as FencedWorkflowStore).claimRunExecution(
        watcherRaceRunId,
        ownerId: 'watcher-race-test',
      ))!;

      await first!.registerWatcher(
        watcherRaceRunId,
        'event-step',
        'stale.topic',
      );
      // Re-registering on the second connection replaces the watcher and
      // makes the requested topic a stale candidate for the resolver.
      await second!.registerWatcher(
        watcherRaceRunId,
        'event-step',
        'current.topic',
      );

      final outcomes = await Future.wait([
        first!.resolveWatchers('stale.topic', const {'value': 1}),
        (second! as FencedWorkflowStore).markFailedForExecution(
          watcherRaceRunId,
          executionId: claim.executionId,
          error: StateError('terminal'),
          stack: StackTrace.empty,
        ),
      ]);

      expect(outcomes[0], isEmpty);
      expect(
        outcomes[1],
        anyOf(
          TerminalFailureResult.applied,
          TerminalFailureResult.alreadyFailedForExecution,
        ),
      );
      expect(
        (await store.get(watcherRaceRunId))!.status,
        WorkflowStatus.failed,
      );
      expect(await first!.listWatchers('current.topic'), isEmpty);
    },
  );
}
