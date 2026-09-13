import 'dart:async';

import 'package:stem/memory.dart';
import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  test(
    'repairs a missing continuation without repeating a checkpoint',
    () async {
      final store = InMemoryWorkflowStore();
      var preparations = 0;
      const event = WorkflowEventRef<Map<String, Object?>>(
        topic: 'recover.ready',
      );
      final workflow = HostedWorkflow<String, String>(
        name: 'recover.workflow',
        run: (context, input) async {
          final prepared = await context.step('prepare', () {
            preparations++;
            return input.toUpperCase();
          });
          await context.awaitEvent('ready', event);
          return prepared;
        },
      );
      final original = await StemWorkflowApp.create(
        workflows: [workflow.bind(PayloadCodecRegistry())],
        storeFactory: WorkflowStoreFactory(create: () async => store),
      );
      addTearDown(original.close);
      final id = await original.startWorkflow(
        workflow.name,
        params: const {'input': 'persisted'},
      );
      await original.executeRun(id);
      expect(preparations, 1);
      // Simulate the persisted-event / missing-continuation crash boundary.
      await store.resolveWatchers(event.topic, const {});
      await original.close();

      final host = await WorkflowHost.create(
        workflows: [workflow],
        createApp: (definitions) => StemWorkflowApp.create(
          workflows: definitions,
          storeFactory: WorkflowStoreFactory(create: () async => store),
        ),
      );
      addTearDown(host.close);
      final report = await host.recover();
      expect(report.enqueuedRunIds, [id]);
      expect(report.errors, isEmpty);
      final run = await host.observe(workflow, id);
      expect(await run.result.timeout(const Duration(seconds: 3)), 'PERSISTED');
      expect(preparations, 1);
    },
  );

  test('overlapping recovery scans coalesce and close joins them', () async {
    final store = _RecoveryStore()..gate = Completer<void>();
    final workflow = _workflow();
    final app = await _app(store, workflow);
    addTearDown(app.close);
    final host = await WorkflowHost.attach(app: app, workflows: [workflow]);
    addTearDown(() async {
      if (!store.gate!.isCompleted) store.gate!.complete();
      await host.close();
    });
    final id = await store.createRun(
      workflow: workflow.name,
      params: const {'input': 'value'},
    );
    final first = host.recover(limit: 1);
    final second = host.recover(limit: 2);
    expect(identical(first, second), isTrue);
    await store.entered.future;
    var closed = false;
    final closing = host.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    store.gate!.complete();
    final report = await first;
    await closing;
    expect(report.enqueuedRunIds, [id]);
    expect(store.scans, 1);
    expect(host.recover, throwsStateError);
  });

  test('rechecks stale candidates and reports individual failures', () async {
    final store = _RecoveryStore();
    final workflow = _workflow();
    final app = await _app(store, workflow);
    addTearDown(app.close);
    final host = await WorkflowHost.attach(app: app, workflows: [workflow]);
    addTearDown(host.close);
    Future<String> create(String id, {String? name}) => store.createRun(
      runId: id,
      workflow: name ?? workflow.name,
      params: const {'input': 'value'},
    );
    final ready = await create('ready');
    final completed = await create('completed');
    await store.markCompleted(completed, 'done');
    final leased = await create('leased');
    await store.claimRunExecution(
      leased,
      ownerId: 'another-worker',
      leaseDuration: const Duration(days: 1),
    );
    final unknown = await create('unknown', name: 'not.registered');
    final broken = await create('broken');
    store
      ..brokenId = broken
      ..candidates = [ready, completed, leased, unknown, broken, 'missing'];
    final report = await host.recover();
    expect(report.enqueuedRunIds, [ready]);
    expect(report.skippedRunIds, [completed, leased, unknown, 'missing']);
    expect(report.errors.keys, [broken]);
    expect(
      () => report.enqueuedRunIds.add('mutation'),
      throwsUnsupportedError,
    );
    expect(report.errors.clear, throwsUnsupportedError);
  });
}

HostedWorkflow<String, String> _workflow() => HostedWorkflow<String, String>(
  name: 'recover.fixture',
  run: (_, input) => input,
);

Future<StemWorkflowApp> _app(
  InMemoryWorkflowStore store,
  HostedWorkflow<String, String> workflow,
) => StemWorkflowApp.create(
  workflows: [workflow.bind(PayloadCodecRegistry())],
  storeFactory: WorkflowStoreFactory(create: () async => store),
);

class _RecoveryStore extends InMemoryWorkflowStore {
  int scans = 0;
  String? brokenId;
  List<String>? candidates;
  Completer<void>? gate;
  final entered = Completer<void>();

  @override
  Future<List<String>> listRunnableRuns({
    DateTime? now,
    int limit = 50,
    int offset = 0,
  }) async {
    scans++;
    if (!entered.isCompleted) entered.complete();
    if (gate != null) await gate!.future;
    return candidates?.skip(offset).take(limit).toList() ??
        await super.listRunnableRuns(now: now, limit: limit, offset: offset);
  }

  @override
  Future<RunState?> get(String runId) {
    if (runId == brokenId) throw StateError('store unavailable for $runId');
    return super.get(runId);
  }
}
