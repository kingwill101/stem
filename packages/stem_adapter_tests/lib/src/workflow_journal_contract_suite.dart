import 'package:stem/stem.dart';
import 'package:stem_adapter_tests/src/workflow_store_contract_suite.dart';
import 'package:test/test.dart';

/// Verifies journal CAS, real checkpoint coupling, and cleanup registration.
void runWorkflowJournalContractTests({
  required String adapterName,
  required WorkflowStoreContractFactory factory,
}) {
  group('$adapterName workflow journals', () {
    late WorkflowStore store;
    late WorkflowJournalStore journal;
    late FencedWorkflowStore fenced;
    late String id;
    late String executionId;

    setUp(() async {
      store = await factory.create(FakeWorkflowClock(DateTime.utc(2024)));
      journal = store as WorkflowJournalStore;
      fenced = store as FencedWorkflowStore;
      id = await store.createRun(
        workflow: 'journal.contract',
        params: const {},
      );
      executionId = (await fenced.claimRunExecution(
        id,
        ownerId: 'owner',
      ))!.executionId;
    });
    tearDown(() async {
      await factory.dispose?.call(store);
    });

    WorkflowJournalEntry entry(String name, int revision) =>
        WorkflowJournalEntry(
          runId: id,
          kind: WorkflowJournalKind.step,
          name: name,
          revision: revision,
          data: const {'version': 1, 'state': 'running', 'attempts': 1},
        );

    Future<void> save(String name, Object? value) async {
      expect(
        await journal.commitJournal(
          entry(name, 1),
          expectedRevision: 0,
          executionId: executionId,
          checkpoint: WorkflowJournalCheckpoint(
            value: value,
            compensation: WorkflowCompensationRegistration(
              handler: 'undo',
              input: value,
            ),
          ),
        ),
        isTrue,
      );
    }

    void invalidWrite(
      String description,
      WorkflowJournalEntry Function() build, {
      int expectedRevision = 0,
      WorkflowJournalCheckpoint? checkpoint,
    }) {
      test('malformed write: $description', () async {
        final write = build();
        final before = (await store.get(id))!.toJson();
        await expectLater(
          journal.commitJournal(
            write,
            expectedRevision: expectedRevision,
            executionId: executionId,
            checkpoint: checkpoint,
          ),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.message,
              'message',
              'Invalid workflow journal write.',
            ),
          ),
        );
        expect((await store.get(id))!.toJson(), before);
        expect(await store.listSteps(id), isEmpty);
        expect(await journal.listCompensations(id), isEmpty);
        expect(
          (await journal.readJournal(id, write.kind, write.name))!.entry,
          isNull,
        );
        if (write.runId != id) expect(await store.get(write.runId), isNull);
      });
    }

    invalidWrite(
      'negative expected revision',
      () => entry('step', 0),
      expectedRevision: -1,
    );
    invalidWrite('inconsistent next revision', () => entry('step', 2));
    for (final name in ['', ' \t']) {
      invalidWrite('blank name ${name.length}', () => entry(name, 1));
    }
    for (final runId in ['', ' \t']) {
      invalidWrite(
        'blank run ID ${runId.length}',
        () => WorkflowJournalEntry(
          runId: runId,
          kind: WorkflowJournalKind.step,
          name: 'step',
          revision: 1,
          data: const {},
        ),
      );
    }
    invalidWrite(
      'checkpoint on a compensation record',
      () => WorkflowJournalEntry(
        runId: id,
        kind: WorkflowJournalKind.compensation,
        name: 'cleanup',
        revision: 1,
        data: const {},
      ),
      checkpoint: const WorkflowJournalCheckpoint(value: 'must not appear'),
    );

    test('journal-only CAS never appears as an ordinary checkpoint', () async {
      expect(
        await journal.commitJournal(
          entry('step', 1),
          expectedRevision: 0,
          executionId: executionId,
        ),
        isTrue,
      );
      expect(
        await journal.commitJournal(
          entry('step', 1),
          expectedRevision: 0,
          executionId: executionId,
          checkpoint: const WorkflowJournalCheckpoint(value: 'must not appear'),
        ),
        isFalse,
      );
      expect(await store.listSteps(id), isEmpty);
      expect((await store.get(id))!.cursor, 0);
      expect(
        (await journal.readJournal(
          id,
          WorkflowJournalKind.step,
          'step',
        ))!.entry!.revision,
        1,
      );
    });

    test('an empty token cannot write an unclaimed run', () async {
      final unclaimed = await store.createRun(
        workflow: 'journal.unclaimed',
        params: const {},
      );
      expect(
        await journal.commitJournal(
          WorkflowJournalEntry(
            runId: unclaimed,
            kind: WorkflowJournalKind.step,
            name: 'step',
            revision: 1,
            data: const {'version': 1, 'state': 'completed'},
          ),
          expectedRevision: 0,
          executionId: '',
          checkpoint: const WorkflowJournalCheckpoint(value: 'unowned'),
        ),
        isFalse,
      );
      expect(await store.listSteps(unclaimed), isEmpty);
      expect(
        (await journal.readJournal(
          unclaimed,
          WorkflowJournalKind.step,
          'step',
        ))!.entry,
        isNull,
      );
    });

    test(
      'fence rejects stale writes without partial checkpoint effects',
      () async {
        final stale = executionId;
        await fenced.releaseRunExecution(id, executionId: executionId);
        executionId = (await fenced.claimRunExecution(
          id,
          ownerId: 'owner',
        ))!.executionId;
        expect(
          await journal.commitJournal(
            entry('step', 1),
            expectedRevision: 0,
            executionId: stale,
            checkpoint: const WorkflowJournalCheckpoint(value: 'stale'),
          ),
          isFalse,
        );
        expect(await store.listSteps(id), isEmpty);
        await save('step', const {'value': 'current'});
        expect(await store.readStep<Object?>(id, 'step'), {'value': 'current'});
        expect((await store.listSteps(id)).map((step) => step.name), ['step']);
        expect((await store.get(id))!.cursor, 1);
      },
    );

    test('successful values register ordered cleanup atomically', () async {
      await save('first', const {'value': 1});
      await save('second', const {'value': 2});
      final records = await journal.listCompensations(id);
      expect(records.map((record) => record.name), ['second', 'first']);
      expect(records.map((record) => record.position), [2, 1]);
      expect(records.first.data['input'], {'value': 2});
      expect(records.first.data['handler'], 'undo');
      final first = records.first;
      final update = WorkflowJournalEntry(
        runId: id,
        kind: first.kind,
        name: first.name,
        revision: 2,
        data: {...first.data, 'state': 'completed'},
      );
      expect(
        await journal.commitJournal(
          update,
          expectedRevision: 1,
          executionId: executionId,
        ),
        isFalse,
      );
      await fenced.markFailedForExecution(
        id,
        executionId: executionId,
        error: StateError('terminal'),
        stack: StackTrace.empty,
      );
      expect(
        await journal.commitJournal(
          update,
          expectedRevision: 1,
          executionId: executionId,
        ),
        isTrue,
      );
      expect((await journal.listCompensations(id)).first.position, 2);
      expect((await store.listSteps(id)).length, 2);
    });

    test(
      'invalid registration rolls back journal and checkpoint writes',
      () async {
        await expectLater(
          journal.commitJournal(
            entry('invalid', 1),
            expectedRevision: 0,
            executionId: executionId,
            checkpoint: const WorkflowJournalCheckpoint(
              value: 'must not appear',
              compensation: WorkflowCompensationRegistration(
                handler: 'undo',
                input: 1,
                retryPolicy: WorkflowRetryPolicy(maxAttempts: 0),
              ),
            ),
          ),
          throwsArgumentError,
        );
        expect(
          (await journal.readJournal(
            id,
            WorkflowJournalKind.step,
            'invalid',
          ))!.entry,
          isNull,
        );
        expect(await store.listSteps(id), isEmpty);
        expect(await journal.listCompensations(id), isEmpty);
      },
    );

    test(
      'rewind discards removed-step journals and fences old cleanup',
      () async {
        const retained = "first'checkpoint";
        await save(retained, 1);
        await save('second', 2);
        await save('third', 3);
        await fenced.markFailedForExecution(
          id,
          executionId: executionId,
          error: StateError('terminal'),
          stack: StackTrace.empty,
        );
        final old = (await journal.listCompensations(id)).first;
        await store.rewindToStep(id, 'second');
        expect((await journal.listCompensations(id)).map((e) => e.name), [
          retained,
        ]);
        for (final removed in ['second', 'third']) {
          expect(
            (await journal.readJournal(
              id,
              WorkflowJournalKind.step,
              removed,
            ))!.entry,
            isNull,
          );
        }
        expect((await store.listSteps(id)).map((step) => step.name), [
          retained,
        ]);
        expect(
          await journal.commitJournal(
            WorkflowJournalEntry(
              runId: id,
              kind: old.kind,
              name: old.name,
              revision: old.revision + 1,
              data: old.data,
            ),
            expectedRevision: old.revision,
            executionId: executionId,
          ),
          isFalse,
        );
        await store.rewindToStep(id, retained);
        expect(await journal.listCompensations(id), isEmpty);
        expect(await store.listSteps(id), isEmpty);
        expect(
          (await journal.readJournal(
            id,
            WorkflowJournalKind.step,
            retained,
          ))!.entry,
          isNull,
        );
      },
    );
  });
}
