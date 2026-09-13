import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stem/memory.dart';
import 'package:stem_flutter/stem_flutter.dart';

void main() {
  test(
    'dispose joins a pending owned factory without late notifications',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final gate = Completer<WorkflowHost>();
      var factoryCalls = 0;
      final controller = WorkflowHostController(
        factory: () {
          factoryCalls++;
          return gate.future;
        },
      );
      var notifications = 0;
      controller.addListener(() => notifications++);
      final first = controller.start();
      expect(identical(first, controller.start()), isTrue);
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
      final atDispose = notifications;
      gate.complete(fixture.host);
      await controller.close();
      await first;
      expect(factoryCalls, 1);
      expect(fixture.host.isClosed, isTrue);
      expect(controller.host, isNull);
      expect(notifications, atDispose);
    },
  );

  test(
    'startup errors are visible and reporter errors do not escape',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final failure = StateError('factory unavailable');
      var fail = true;
      var reports = 0;
      final controller = WorkflowHostController(
        factory: () {
          if (fail) throw failure;
          return Future.value(fixture.host);
        },
        onError: (_, _) {
          reports++;
          throw StateError('reporter unavailable');
        },
      );
      addTearDown(controller.dispose);
      await controller.start();
      expect(controller.error, same(failure));
      expect(controller.isLoading, isFalse);
      expect(reports, 1);
      fail = false;
      await controller.start();
      expect(controller.error, isNull);
      expect(controller.host, same(fixture.host));
      await controller.close();
    },
  );

  test('borrowed hosts survive close and recovery requests coalesce', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final controller = WorkflowHostController(host: fixture.host);
    addTearDown(controller.dispose);
    await controller.start();
    expect(fixture.store.scans, 1);
    fixture.store.gate = Completer<void>();
    final a = controller.recover();
    final b = controller.recover();
    expect(identical(a, b), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(fixture.store.scans, 2);
    fixture.store.gate!.complete();
    await a;
    expect(controller.recoveryReport, isNotNull);
    await controller.close();
    expect(fixture.host.isClosed, isFalse);
  });

  testWidgets('scope recovers on foreground only and detaches cleanly', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    final controller = WorkflowHostController(host: fixture.host);
    await tester.pumpWidget(
      WorkflowHostScope(
        controller: controller,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: Text('ready'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('ready'), findsOneWidget);
    expect(fixture.store.scans, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(fixture.store.scans, 1);
    fixture.store.gate = Completer<void>();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(fixture.store.scans, 2);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    fixture.store.gate!.complete();
    await tester.pump();
    await controller.close();
    expect(tester.takeException(), isNull);
    expect(fixture.host.isClosed, isFalse);
    await fixture.close();
  });

  testWidgets('run builder preserves its subscription across parent rebuilds', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    final id = await fixture.store.createRun(
      workflow: fixture.workflow.name,
      params: const {'input': 'value'},
    );
    final run = await fixture.host.observe(fixture.workflow, id);
    fixture.store.reads = 0;
    Widget build() => Directionality(
      textDirection: TextDirection.ltr,
      child: HostedRunBuilder<String>(
        run: run,
        builder: (_, state) => Text(state.status.name),
      ),
    );
    await tester.pumpWidget(build());
    await tester.pump();
    expect(find.text('running'), findsOneWidget);
    final reads = fixture.store.reads;
    await tester.pumpWidget(build());
    await tester.pump();
    expect(fixture.store.reads, reads);
    await tester.pumpWidget(const SizedBox());
    final closing = fixture.close();
    // Native cancellation and fake frame scheduling must both progress.
    // Bound the event-loop turns so teardown cannot silently hang the test.
    var closed = false;
    unawaited(closing.then((_) => closed = true));
    for (var i = 0; i < 10 && !closed; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    expect(closed, isTrue);
    await closing;
  });
}

class _Fixture {
  _Fixture(this.store, this.app, this.host, this.workflow);

  final _Store store;
  final StemWorkflowApp app;
  final WorkflowHost host;
  final HostedWorkflow<String, String> workflow;

  static Future<_Fixture> create() async {
    final store = _Store();
    final workflow = HostedWorkflow<String, String>(
      name: 'flutter.binding',
      run: (_, input) => input,
    );
    final app = await StemWorkflowApp.create(
      workflows: [workflow.bind(PayloadCodecRegistry())],
      storeFactory: WorkflowStoreFactory(create: () async => store),
    );
    final host = await WorkflowHost.attach(app: app, workflows: [workflow]);
    return _Fixture(store, app, host, workflow);
  }

  Future<void> close() async {
    if (store.gate != null && !store.gate!.isCompleted) store.gate!.complete();
    await host.close();
    await app.close();
  }
}

class _Store extends InMemoryWorkflowStore {
  int scans = 0;
  int reads = 0;
  Completer<void>? gate;

  @override
  Future<List<String>> listRunnableRuns({
    DateTime? now,
    int limit = 50,
    int offset = 0,
  }) async {
    scans++;
    if (gate != null) await gate!.future;
    return super.listRunnableRuns(now: now, limit: limit, offset: offset);
  }

  @override
  Future<RunState?> get(String runId) {
    reads++;
    return super.get(runId);
  }
}
