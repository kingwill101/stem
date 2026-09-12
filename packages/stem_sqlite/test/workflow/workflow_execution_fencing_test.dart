import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_sqlite/stem_sqlite.dart';
import 'package:test/test.dart';

void main() {
  test('independent handles preserve execution fences across reopen', () async {
    final directory = await Directory.systemTemp.createTemp('sqlite-fence-');
    final file = File('${directory.path}/workflows.sqlite');
    final clock = FakeWorkflowClock(DateTime.utc(2024));
    final stores = <SqliteWorkflowStore>[];
    addTearDown(() async {
      for (final store in stores) {
        await store.close();
      }
      await directory.delete(recursive: true);
    });
    Future<SqliteWorkflowStore> open() async {
      final store = await SqliteWorkflowStore.open(file, clock: clock);
      stores.add(store);
      return store;
    }

    final first = await open();
    final second = await open();
    final id = await first.createRun(workflow: 'fences', params: const {});
    final claimA = (await first.claimRunExecution(id, ownerId: 'same'))!;
    expect(await second.claimRunExecution(id, ownerId: 'same'), isNull);
    await first.releaseRunExecution(id, executionId: claimA.executionId);
    final claimB = (await second.claimRunExecution(id, ownerId: 'same'))!;
    expect(claimB.executionId, isNot(claimA.executionId));
    expect(
      await first.markFailedForExecution(
        id,
        executionId: claimA.executionId,
        error: StateError('stale'),
        stack: StackTrace.empty,
      ),
      TerminalFailureResult.superseded,
    );
    await first.releaseRunExecution(id, executionId: claimA.executionId);
    expect((await second.get(id))!.ownerId, 'same');
    await second.markCompleted(id, 'new owner result');
    await first.close();
    await second.close();
    stores.clear();

    final reopened = await open();
    expect((await reopened.get(id))!.executionId, claimB.executionId);
    expect(
      await reopened.markFailedForExecution(
        id,
        executionId: claimB.executionId,
        error: StateError('late'),
        stack: StackTrace.empty,
      ),
      TerminalFailureResult.superseded,
    );
    expect((await reopened.get(id))!.result, 'new owner result');

    final failedId = await reopened.createRun(
      workflow: 'failed',
      params: const {},
    );
    final failedClaim = (await reopened.claimRunExecution(
      failedId,
      ownerId: 'owner',
    ))!;
    expect(
      await reopened.markFailedForExecution(
        failedId,
        executionId: failedClaim.executionId,
        error: StateError('failed'),
        stack: StackTrace.empty,
      ),
      TerminalFailureResult.applied,
    );
    await reopened.close();
    stores.clear();
    final recovered = await open();
    expect(
      await recovered.markFailedForExecution(
        failedId,
        executionId: failedClaim.executionId,
        error: StateError('repeated callback'),
        stack: StackTrace.empty,
      ),
      TerminalFailureResult.alreadyFailedForExecution,
    );
    expect(
      (await recovered.get(failedId))!.lastError?['error'],
      contains('failed'),
    );
  });
}
