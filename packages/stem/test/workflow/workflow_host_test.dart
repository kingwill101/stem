import 'dart:async';

import 'package:stem/memory.dart';
import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  test(
    'uses registered codecs and bodies for equivalent definitions',
    () async {
      final workflow = HostedWorkflow<String, String>(
        name: 'canonical',
        run: (context, input) => context.step('echo', () => input),
      );
      final registry = PayloadCodecRegistry();
      final host = await WorkflowHost.create(
        workflows: [workflow],
        codecs: registry,
        createApp: (definitions) async {
          // Binding and the host must use the same snapshot across this await.
          registry.register<String>(
            PayloadCodec<String>(
              encode: (_) => throw StateError('mutated codec used'),
              decode: (_) => throw StateError('mutated codec used'),
            ),
          );
          return StemWorkflowApp.inMemory(workflows: definitions);
        },
      );
      addTearDown(host.close);
      final foreign = HostedWorkflow<String, String>(
        name: workflow.name,
        inputCodec: PayloadCodec<String>(
          encode: (_) => throw StateError('foreign input codec'),
          decode: (_) => throw StateError('foreign input codec'),
        ),
        resultCodec: PayloadCodec<String>(
          encode: (_) => throw StateError('foreign result codec'),
          decode: (_) => throw StateError('foreign result codec'),
        ),
        run: (_, input) => throw StateError('foreign body'),
      );
      final run = await host.submit(foreign, 'original');
      expect(await run.result, 'original');
      final reattached = await host.observe(foreign, run.id);
      expect(await reattached.result, 'original');
      await expectLater(
        host.submit(
          HostedWorkflow<int, int>(
            name: workflow.name,
            run: (_, value) => value,
          ),
          1,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'nullable results and checkpoint values survive typed decoding',
    () async {
      final workflow = HostedWorkflow<String?, String?>(
        name: 'nullable',
        run: (context, input) => context.step<String?>('echo', () => input),
      );
      final host = await WorkflowHost.inMemory(workflows: [workflow]);
      addTearDown(host.close);
      expect(await host.execute(workflow, null), isNull);
      expect(await host.execute(workflow, 'value'), 'value');
    },
  );

  test('observation timeout does not cancel a run', () async {
    final workflow = _waitingWorkflow('timeout');
    final host = await WorkflowHost.inMemory(
      workflows: [workflow],
      resultTimeout: const Duration(milliseconds: 20),
      pollInterval: const Duration(milliseconds: 5),
    );
    addTearDown(host.close);
    final run = await host.submit(workflow, 'input');
    await expectLater(run.result, throwsA(isA<TimeoutException>()));
    await _suspended(run);
    expect((await run.status()).status, WorkflowStatus.suspended);
    await host.emitEvent(
      const WorkflowEventRef<Map<String, Object?>>(topic: 'timeout'),
      {'answer': 'yes'},
    );
    await run
        .watch()
        .firstWhere(
          (view) => view.status == WorkflowStatus.completed,
        )
        .timeout(const Duration(seconds: 5));
    expect(await (await host.observe(workflow, run.id)).result, 'yes');
  });

  test(
    'close stops results and streams but leaves a borrowed app alive',
    () async {
      final workflow = _waitingWorkflow('borrowed');
      final app = await StemWorkflowApp.inMemory(
        workflows: [workflow.bind(PayloadCodecRegistry())],
      );
      addTearDown(app.close);
      final host = await WorkflowHost.attach(app: app, workflows: [workflow]);
      expect(app.isStarted, isFalse);
      await app.start();
      final run = await host.submit(workflow, 'input');
      final observation = expectLater(run.result, throwsStateError);
      await _suspended(run);
      final done = Completer<void>();
      final subscription = run.watch().listen((_) {}, onDone: done.complete);
      addTearDown(subscription.cancel);
      final closing = host.close();
      expect(identical(closing, host.close()), isTrue);
      await closing;
      await observation;
      await done.future.timeout(const Duration(seconds: 2));
      expect(app.isStarted, isTrue);
      expect((await app.viewRun(run.id))!.status, WorkflowStatus.suspended);
      expect(run.status, throwsStateError);
      expect(run.cancel, throwsStateError);
    },
  );

  test('durable cancellation settles the result as cancelled', () async {
    final workflow = _waitingWorkflow('cancel');
    final host = await WorkflowHost.inMemory(workflows: [workflow]);
    addTearDown(host.close);
    final run = await host.submit(workflow, 'input');
    await _suspended(run);
    final result = expectLater(
      run.result,
      throwsA(
        isA<HostedWorkflowFailure>().having(
          (failure) => failure.status,
          'status',
          WorkflowStatus.cancelled,
        ),
      ),
    );
    await run.cancel();
    await result;
    expect((await run.status()).status, WorkflowStatus.cancelled);
  });

  test('close joins admitted submission before owned app cleanup', () async {
    final workflow = _waitingWorkflow('admission');
    late StemWorkflowApp app;
    final host = await WorkflowHost.create(
      workflows: [workflow],
      createApp: (definitions) async =>
          app = await StemWorkflowApp.inMemory(workflows: definitions),
    );
    final entered = Completer<void>();
    final release = Completer<void>();
    final listener = StemSignals.workflowRunStarted.connect((payload, _) async {
      if (payload.workflow == workflow.name) {
        entered.complete();
        await release.future;
      }
    });
    addTearDown(listener.cancel);
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await host.close();
    });
    final pending = host.submit(workflow, 'input');
    await entered.future.timeout(const Duration(seconds: 2));
    var closed = false;
    final closing = host.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    expect(app.isStarted, isTrue);
    release.complete();
    await pending;
    await closing;
    expect(app.isStarted, isFalse);
  });

  test('failed initialization cleans up the returned owned app', () async {
    var disposed = 0;
    final store = InMemoryWorkflowStore();
    final workflow = _waitingWorkflow('not-registered');
    await expectLater(
      WorkflowHost.create(
        workflows: [workflow],
        createApp: (_) => StemWorkflowApp.create(
          storeFactory: WorkflowStoreFactory(
            create: () async => store,
            dispose: (_) async {
              disposed++;
            },
          ),
        ),
      ),
      throwsArgumentError,
    );
    expect(disposed, 1);
  });

  test(
    'active subscriptions share reads and stop after cancellation',
    () async {
      final store = _CountingStore();
      final workflow = _waitingWorkflow('shared');
      final app = await StemWorkflowApp.create(
        storeFactory: WorkflowStoreFactory(create: () async => store),
        workflows: [workflow.bind(PayloadCodecRegistry())],
      );
      addTearDown(app.close);
      final host = await WorkflowHost.attach(app: app, workflows: [workflow]);
      addTearDown(host.close);
      final id = await store.createRun(
        workflow: workflow.name,
        params: const {'input': 'value'},
      );
      final a = await host.observe(workflow, id);
      final b = await host.observe(workflow, id);
      store.reads = 0;
      final values = await Future.wait([a.watch().first, b.watch().first]);
      expect(values.map((view) => view.runId), [id, id]);
      expect(store.reads, 1);
      await host.close();
      expect(store.reads, 1);
    },
  );

  test('unsubscribe and close cancel long observation timers', () async {
    final store = _CountingStore();
    final workflow = _waitingWorkflow('timer');
    final app = await StemWorkflowApp.create(
      storeFactory: WorkflowStoreFactory(
        create: () async => _PollingStore(store),
      ),
      workflows: [workflow.bind(PayloadCodecRegistry())],
    );
    addTearDown(app.close);
    final host = await WorkflowHost.attach(
      app: app,
      workflows: [workflow],
      pollInterval: const Duration(hours: 1),
    );
    addTearDown(host.close);
    final id = await store.createRun(
      workflow: workflow.name,
      params: const {'input': 'value'},
    );
    final run = await host.observe(workflow, id);
    final timers = <Timer>[];
    Future<StreamSubscription<WorkflowRunView>> subscribe() async {
      final received = Completer<void>();
      final subscription = runZoned(
        () => run.watch().listen((_) {
          if (!received.isCompleted) received.complete();
        }),
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            final timer = parent.createTimer(zone, duration, callback);
            timers.add(timer);
            return timer;
          },
        ),
      );
      await received.future;
      return subscription;
    }

    final first = await subscribe();
    expect(timers.where((timer) => timer.isActive), hasLength(1));
    await first.cancel();
    expect(timers.any((timer) => timer.isActive), isFalse);
    final second = await subscribe();
    addTearDown(second.cancel);
    expect(timers.where((timer) => timer.isActive), hasLength(1));
    await host.close();
    expect(timers.any((timer) => timer.isActive), isFalse);
  });

  test('invalid configuration fails before creating resources', () async {
    var created = false;
    final workflow = _waitingWorkflow('duplicate');
    Future<StemWorkflowApp> factory(List<WorkflowDefinition> definitions) {
      created = true;
      return StemWorkflowApp.inMemory(workflows: definitions);
    }

    await expectLater(
      WorkflowHost.create(createApp: factory, workflows: [workflow, workflow]),
      throwsArgumentError,
    );
    await expectLater(
      WorkflowHost.create(
        createApp: factory,
        workflows: [workflow],
        resultTimeout: Duration.zero,
      ),
      throwsArgumentError,
    );
    expect(created, isFalse);
  });
}

HostedWorkflow<String, String> _waitingWorkflow(String name) =>
    HostedWorkflow<String, String>(
      name: name,
      run: (context, _) async {
        final event = await context.awaitEvent(
          'wait',
          WorkflowEventRef<Map<String, Object?>>(topic: name),
        );
        return event['answer']! as String;
      },
    );

Future<void> _suspended(HostedRun<String> run) async {
  await run
      .watch()
      .firstWhere(
        (view) => view.status == WorkflowStatus.suspended,
      )
      .timeout(const Duration(seconds: 5));
}

class _CountingStore extends InMemoryWorkflowStore {
  int reads = 0;

  @override
  Future<RunState?> get(String runId) {
    reads++;
    return super.get(runId);
  }
}

class _PollingStore implements WorkflowStore {
  _PollingStore(this.delegate);
  final InMemoryWorkflowStore delegate;

  @override
  Future<RunState?> get(String runId) => delegate.get(runId);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected polling-fixture store call.');
}
