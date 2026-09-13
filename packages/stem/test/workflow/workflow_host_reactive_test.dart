import 'dart:async';

import 'package:stem/memory.dart';
import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  test(
    'native changes eliminate idle polling and still deliver terminal state',
    () async {
      final store = _CountedStore();
      final fixture = await _Fixture.create(store);
      addTearDown(fixture.close);
      final run = await fixture.host.observe(fixture.workflow, fixture.id);
      store.reads = 0;
      final initial = Completer<void>();
      final done = Completer<void>();
      final timers = <Timer>[];
      final states = <WorkflowStatus>[];
      final subscription = runZoned(
        () => run.watch().listen((view) {
          states.add(view.status);
          if (!initial.isCompleted) initial.complete();
        }, onDone: done.complete),
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            final timer = parent.createTimer(zone, duration, callback);
            timers.add(timer);
            return timer;
          },
        ),
      );
      await initial.future;
      expect(store.reads, 1);
      expect(timers, isEmpty);
      await store.markCompleted(fixture.id, 'wire');
      await done.future.timeout(const Duration(seconds: 2));
      expect(states, [WorkflowStatus.running, WorkflowStatus.completed]);
      await subscription.cancel();
    },
  );

  test('a broken native source falls back to bounded polling', () async {
    final store = _BrokenChangesStore();
    final fixture = await _Fixture.create(store);
    addTearDown(fixture.close);
    final run = await fixture.host.observe(fixture.workflow, fixture.id);
    final initial = Completer<void>();
    final completed = Completer<void>();
    final errors = <Object>[];
    final subscription = run.watch().listen((view) {
      if (!initial.isCompleted) initial.complete();
      if (view.status == WorkflowStatus.completed) completed.complete();
    }, onError: errors.add);
    addTearDown(subscription.cancel);
    await initial.future;
    await store.markCompleted(fixture.id, 'wire');
    await completed.future.timeout(const Duration(seconds: 2));
    expect(errors, isEmpty);
  });

  test('owned close joins native subscription cleanup', () async {
    final store = _GatedChangesStore();
    final fixture = await _Fixture.create(store, owned: true);
    final run = await fixture.host.observe(fixture.workflow, fixture.id);
    final initial = Completer<void>();
    final subscription = run.watch().listen((_) {
      if (!initial.isCompleted) initial.complete();
    });
    addTearDown(() async {
      if (!store.cancelGate.isCompleted) store.cancelGate.complete();
      await subscription.cancel();
      await fixture.close();
    });
    await initial.future;
    var closed = false;
    final closing = fixture.host.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    store.cancelGate.complete();
    await closing;
    expect(fixture.app.isStarted, isFalse);
  });

  test('native cleanup failure still closes the owned app', () async {
    final failure = StateError('unsubscribe failed');
    final fixture = await _Fixture.create(
      _FailedCleanupStore(failure),
      owned: true,
    );
    addTearDown(fixture.app.close);
    final run = await fixture.host.observe(fixture.workflow, fixture.id);
    final initial = Completer<void>();
    final subscription = run.watch().listen((_) {
      if (!initial.isCompleted) initial.complete();
    });
    await initial.future;
    await expectLater(fixture.host.close(), throwsA(same(failure)));
    await subscription.cancel();
    expect(fixture.app.isStarted, isFalse);
  });
}

class _Fixture {
  _Fixture(this.app, this.host, this.workflow, this.id);
  final StemWorkflowApp app;
  final WorkflowHost host;
  final HostedWorkflow<String, String> workflow;
  final String id;

  static Future<_Fixture> create(
    InMemoryWorkflowStore store, {
    bool owned = false,
  }) async {
    final workflow = HostedWorkflow<String, String>(
      name: 'reactive',
      run: (_, value) => value,
    );
    late StemWorkflowApp app;
    late WorkflowHost host;
    if (owned) {
      host = await WorkflowHost.create(
        workflows: [workflow],
        createApp: (definitions) async => app = await StemWorkflowApp.create(
          workflows: definitions,
          storeFactory: WorkflowStoreFactory(create: () async => store),
        ),
      );
    } else {
      app = await StemWorkflowApp.create(
        workflows: [workflow.bind(PayloadCodecRegistry())],
        storeFactory: WorkflowStoreFactory(create: () async => store),
      );
      host = await WorkflowHost.attach(
        app: app,
        workflows: [workflow],
        pollInterval: const Duration(milliseconds: 5),
      );
    }
    final id = await store.createRun(
      workflow: workflow.name,
      params: const {'input': 'value'},
    );
    return _Fixture(app, host, workflow, id);
  }

  Future<void> close() async {
    await host.close();
    await app.close();
  }
}

class _CountedStore extends InMemoryWorkflowStore {
  int reads = 0;
  @override
  Future<RunState?> get(String runId) {
    reads++;
    return super.get(runId);
  }
}

class _BrokenChangesStore extends InMemoryWorkflowStore {
  @override
  Stream<void> watchRunChanges(String runId) =>
      throw StateError('Native observation unavailable.');
}

class _GatedChangesStore extends InMemoryWorkflowStore {
  final cancelGate = Completer<void>();
  @override
  Stream<void> watchRunChanges(String runId) =>
      StreamController<void>(onCancel: () => cancelGate.future).stream;
}

class _FailedCleanupStore extends InMemoryWorkflowStore {
  _FailedCleanupStore(this.failure);
  final Object failure;

  @override
  Stream<void> watchRunChanges(String runId) => StreamController<void>(
    onCancel: () => Future<void>.error(failure),
  ).stream;
}
