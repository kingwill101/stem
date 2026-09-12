import 'dart:async';

import 'package:stem/memory.dart';
import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  test(
    'custom stores cannot silently use unsafe hosted cancellation',
    () async {
      final store = _LegacyStore();
      final workflow = HostedWorkflow<String, String>(
        name: 'legacy.cancel',
        run: (_, value) => value,
      );
      final app = await StemWorkflowApp.create(
        workflows: [workflow.bind(PayloadCodecRegistry())],
        storeFactory: WorkflowStoreFactory(create: () async => store),
      );
      addTearDown(app.close);
      final host = await WorkflowHost.attach(app: app, workflows: [workflow]);
      addTearDown(host.close);
      final id = await store.delegate.createRun(
        workflow: workflow.name,
        params: const {'input': 'value'},
      );
      final run = await host.observe(workflow, id);
      await expectLater(run.cancel(), throwsUnsupportedError);
      expect(store.cancelCalls, 0);
      expect((await run.status()).status, WorkflowStatus.running);
    },
  );

  test(
    'cancelling a completed handle preserves result and emits nothing',
    () async {
      final workflow = HostedWorkflow<String, String>(
        name: 'cancel.completed',
        run: (_, input) => input,
      );
      final host = await WorkflowHost.inMemory(workflows: [workflow]);
      addTearDown(host.close);
      final run = await host.submit(workflow, 'done');
      expect(await run.result, 'done');
      var cancellations = 0;
      final listener = StemSignals.workflowRunCancelled.connect((payload, _) {
        if (payload.runId == run.id) cancellations++;
      });
      addTearDown(listener.cancel);
      await run.cancel();
      expect((await run.status()).status, WorkflowStatus.completed);
      expect(await (await host.observe(workflow, run.id)).result, 'done');
      expect(cancellations, 0);
    },
  );

  test('cancellation wins over an in-flight completion transition', () async {
    final store = _GatedTerminalStore()..gateCompletion = true;
    final workflow = HostedWorkflow<String, String>(
      name: 'cancel.wins',
      run: (_, input) => input,
    );
    final host = await _host(store, workflow);
    addTearDown(() async {
      store.releaseAll();
      await host.close();
    });
    var completions = 0;
    final listener = StemSignals.workflowRunCompleted.connect((payload, _) {
      if (payload.workflow == workflow.name) completions++;
    });
    addTearDown(listener.cancel);
    final run = await host.submit(workflow, 'late completion');
    await store.completing.future.timeout(const Duration(seconds: 3));
    final cancelled = expectLater(
      run.result,
      throwsA(
        isA<HostedWorkflowFailure>().having(
          (error) => error.status,
          'status',
          WorkflowStatus.cancelled,
        ),
      ),
    );
    await run.cancel();
    store.releaseCompletion.complete();
    await store.completionDone.future.timeout(const Duration(seconds: 3));
    await cancelled;
    expect(store.completionApplied, isFalse);
    expect((await run.status()).status, WorkflowStatus.cancelled);
    expect(completions, 0);
  });

  test('completion wins over an in-flight cancellation transition', () async {
    final store = _GatedTerminalStore()..gateCancellation = true;
    final enteredBody = Completer<void>();
    final releaseBody = Completer<void>();
    final workflow = HostedWorkflow<String, String>(
      name: 'complete.wins',
      run: (_, input) async {
        enteredBody.complete();
        await releaseBody.future;
        return input;
      },
    );
    final host = await _host(store, workflow);
    addTearDown(() async {
      if (!releaseBody.isCompleted) releaseBody.complete();
      store.releaseAll();
      await host.close();
    });
    var cancellations = 0;
    final listener = StemSignals.workflowRunCancelled.connect((payload, _) {
      if (payload.workflow == workflow.name) cancellations++;
    });
    addTearDown(listener.cancel);
    final run = await host.submit(workflow, 'done');
    await enteredBody.future.timeout(const Duration(seconds: 3));
    final cancelling = run.cancel();
    await store.cancelling.future.timeout(const Duration(seconds: 3));
    releaseBody.complete();
    expect(await run.result.timeout(const Duration(seconds: 3)), 'done');
    store.releaseCancellation.complete();
    await cancelling;
    expect(store.cancellationApplied, isFalse);
    expect((await run.status()).status, WorkflowStatus.completed);
    expect(cancellations, 0);
  });
}

Future<WorkflowHost> _host(
  InMemoryWorkflowStore store,
  HostedWorkflow<String, String> workflow,
) => WorkflowHost.create(
  workflows: [workflow],
  createApp: (definitions) => StemWorkflowApp.create(
    workflows: definitions,
    storeFactory: WorkflowStoreFactory(create: () async => store),
  ),
);

class _GatedTerminalStore extends InMemoryWorkflowStore {
  bool gateCompletion = false;
  bool gateCancellation = false;
  bool? completionApplied;
  bool? cancellationApplied;
  final completing = Completer<void>();
  final cancelling = Completer<void>();
  final completionDone = Completer<void>();
  final releaseCompletion = Completer<void>();
  final releaseCancellation = Completer<void>();

  void releaseAll() {
    if (!releaseCompletion.isCompleted) releaseCompletion.complete();
    if (!releaseCancellation.isCompleted) releaseCancellation.complete();
  }

  @override
  Future<bool> completeIfActive(String runId, Object? result) async {
    if (gateCompletion) {
      completing.complete();
      await releaseCompletion.future;
    }
    final applied = await super.completeIfActive(runId, result);
    completionApplied = applied;
    if (!completionDone.isCompleted) completionDone.complete();
    return applied;
  }

  @override
  Future<bool> cancelIfActive(String runId, {String? reason}) async {
    if (gateCancellation) {
      cancelling.complete();
      await releaseCancellation.future;
    }
    final applied = await super.cancelIfActive(runId, reason: reason);
    cancellationApplied = applied;
    return applied;
  }
}

// A read-only fixture without the optional atomic terminal capability.
class _LegacyStore implements WorkflowStore {
  final delegate = InMemoryWorkflowStore();
  int cancelCalls = 0;

  @override
  Future<RunState?> get(String runId) => delegate.get(runId);

  @override
  Future<void> cancel(String runId, {String? reason}) async {
    cancelCalls++;
    await delegate.cancel(runId, reason: reason);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected store operation ${invocation.memberName}',
  );
}
