import 'package:stem/memory.dart';
import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  late InMemoryWorkflowStore store;
  late String runId;

  setUp(() async {
    store = InMemoryWorkflowStore();
    runId = await store.createRun(workflow: 'changes', params: const {});
  });

  test('notifies status, checkpoint, and journal mutations', () async {
    var notifications = 0;
    final subscription = store
        .watchRunChanges(runId)
        .listen((_) => notifications++);

    await store.markRunning(runId);
    await store.saveStep(runId, 'step', 'value');
    final executionId = (await store.claimRunExecution(
      runId,
      ownerId: 'owner',
    ))!.executionId;
    final committed = await store.commitJournal(
      WorkflowJournalEntry(
        runId: runId,
        kind: WorkflowJournalKind.step,
        name: 'journal-step',
        revision: 1,
        data: const {'state': 'committed'},
      ),
      expectedRevision: 0,
      executionId: executionId,
    );

    expect(committed, isTrue);
    await pumpEventQueue();
    // markRunning, saveStep, claim, and the journal write each replace _runs.
    expect(notifications, 4);
    await subscription.cancel();
  });

  test('subscription is established before the initial read', () async {
    var notifications = 0;
    final subscription = store
        .watchRunChanges(runId)
        .listen((_) => notifications++);

    final initialRead = store.get(runId);
    await store.saveStep(runId, 'step', 1);
    expect((await initialRead)?.id, runId);
    await pumpEventQueue();

    expect(notifications, 1);
    await subscription.cancel();
  });

  test('removes the controller after its last subscription cancels', () async {
    var oldNotifications = 0;
    final oldSubscription = store
        .watchRunChanges(runId)
        .listen((_) => oldNotifications++);
    await oldSubscription.cancel();

    var newNotifications = 0;
    final newSubscription = store
        .watchRunChanges(runId)
        .listen((_) => newNotifications++);
    await store.markRunning(runId);
    await pumpEventQueue();

    expect(oldNotifications, 0);
    expect(newNotifications, 1);
    await newSubscription.cancel();
  });
}
