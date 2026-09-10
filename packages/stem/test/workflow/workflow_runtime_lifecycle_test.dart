import 'dart:async';

import 'package:contextual/contextual.dart' show LogDriver, LogEntry;
import 'package:stem/memory.dart';
import 'package:stem/src/observability/logging.dart' show stemLogger;
import 'package:stem/stem.dart';
import 'package:test/test.dart';

const _pollInterval = Duration(milliseconds: 5);
const _severalTicks = Duration(milliseconds: 40);

void main() {
  late _GatedStore store;
  late _GatedBroker broker;
  late WorkflowRuntime runtime;

  setUp(() {
    store = _GatedStore();
    broker = _GatedBroker();
    final registry = InMemoryTaskRegistry();
    runtime = WorkflowRuntime(
      stem: Stem(broker: broker, registry: registry),
      store: store,
      eventBus: InMemoryEventBus(store),
      pollInterval: _pollInterval,
    );
    registry.register(runtime.workflowRunnerHandler());
  });

  tearDown(() async {
    if (!store.release.isCompleted) store.release.complete();
    if (!broker.release.isCompleted) broker.release.complete();
    await runtime.dispose();
    broker.dispose();
  });

  test('start admits overdue work before a long polling interval', () async {
    final registry = InMemoryTaskRegistry();
    runtime = WorkflowRuntime(
      stem: Stem(broker: broker, registry: registry),
      store: store,
      eventBus: InMemoryEventBus(store),
      pollInterval: const Duration(hours: 1),
    );
    registry.register(runtime.workflowRunnerHandler());
    final runId = await store.createRun(workflow: 'overdue', params: {});
    await store.suspendUntil(
      runId,
      'sleep',
      DateTime.now().subtract(const Duration(seconds: 1)),
    );

    var started = false;
    final start = runtime.start().then((_) => started = true);
    final concurrentStart = runtime.start();
    await store.entered.future;
    await Future<void>.delayed(_severalTicks);
    expect(started, isFalse);
    expect(store.calls, 1);
    store.release.complete();
    await start;
    await concurrentStart;
    expect(broker.completedPublishes, 1);
    expect(store.calls, 1);
  });

  test(
    'dispose joins dueRuns and prevents overlapping or later polls',
    () async {
      store.gatedCall = 2;
      await runtime.start();
      await store.entered.future;
      await Future<void>.delayed(_severalTicks);
      expect(store.calls, 2);
      expect(store.maxActive, 1);

      var disposed = false;
      final disposal = runtime.dispose().then((_) => disposed = true);
      final secondDisposal = runtime.dispose();
      await Future<void>.delayed(_severalTicks);
      expect(disposed, isFalse);
      expect(store.calls, 2);

      store.release.complete();
      await disposal;
      await secondDisposal;
      expect(store.active, 0);
      await Future<void>.delayed(_severalTicks);
      expect(store.calls, 2);
    },
  );

  test('dispose joins a continuation blocked in enqueue', () async {
    final runId = await store.createRun(workflow: 'sleeping', params: {});
    await store.suspendUntil(
      runId,
      'sleep',
      DateTime.now().subtract(const Duration(seconds: 1)),
    );
    store.release.complete();
    broker.blockPublish = true;
    var started = false;
    final start = runtime.start().then((_) => started = true);
    await broker.entered.future;

    var disposed = false;
    final disposal = runtime.dispose().then((_) => disposed = true);
    await Future<void>.delayed(_severalTicks);
    expect(disposed, isFalse);
    expect(started, isFalse);
    expect(store.calls, 1);
    expect(broker.completedPublishes, 0);

    broker.release.complete();
    await disposal;
    await start;
    expect(broker.completedPublishes, 1);
    await Future<void>.delayed(_severalTicks);
    expect(store.calls, 1);
    expect(broker.completedPublishes, 1);
  });

  test('start waits for draining poll and can restart after dispose', () async {
    final start = runtime.start();
    await store.entered.future;
    final disposal = runtime.dispose();
    var restarted = false;
    final restart = runtime.start().then((_) => restarted = true);
    await Future<void>.delayed(_severalTicks);
    expect(restarted, isFalse);
    expect(store.calls, 1);
    store.release.complete();
    await disposal;
    await start;
    await restart;
    await store.secondEntered.future;
    await runtime.dispose();
    expect(store.maxActive, 1);

    final stoppedCalls = store.calls;
    await runtime.start();
    await Future<void>.delayed(_severalTicks);
    await runtime.dispose();
    expect(store.calls, greaterThan(stoppedCalls));
  });

  test('poll errors are logged and do not fail disposal', () async {
    final driver = _RecordingLogDriver();
    const channel = 'workflow-poll-disposal-test';
    stemLogger.addChannel(channel, driver);
    addTearDown(() => stemLogger.removeChannel(channel));
    final start = runtime.start();
    await store.entered.future;
    final disposal = runtime.dispose();
    store.release.completeError(StateError('poll failed'), StackTrace.current);
    await disposal;
    await start;
    await Future<void>.delayed(Duration.zero);

    final entry = driver.entries.singleWhere(
      (entry) => entry.record.message == 'Workflow polling failed',
    );
    expect(entry.record.context.get('error'), contains('poll failed'));
    expect(entry.record.context.get('stack'), isNotEmpty);
    expect(store.active, 0);

    await runtime.start();
    await store.secondEntered.future;
    await runtime.dispose();
    expect(store.calls, greaterThanOrEqualTo(2));
  });

  test('polling continues after an asynchronous poll failure', () async {
    store.gatedCall = 2;
    await runtime.start();
    await store.entered.future;
    store.release.completeError(StateError('temporary failure'));
    await store.secondEntered.future;
    await runtime.dispose();
    expect(store.maxActive, 1);
  });

  test('immediate dispose cancels start without an initial tick', () async {
    final start = runtime.start();
    await runtime.dispose();
    await start;
    await Future<void>.delayed(_severalTicks);
    expect(store.calls, 0);
  });
}

class _GatedStore extends InMemoryWorkflowStore {
  final entered = Completer<void>();
  final secondEntered = Completer<void>();
  final release = Completer<void>();
  int gatedCall = 1;
  int calls = 0;
  int active = 0;
  int maxActive = 0;

  @override
  Future<List<String>> dueRuns(DateTime now, {int limit = 256}) async {
    calls++;
    active++;
    if (active > maxActive) maxActive = active;
    try {
      if (calls == gatedCall) {
        entered.complete();
        await release.future;
      } else if (calls > gatedCall && !secondEntered.isCompleted) {
        secondEntered.complete();
      }
      return await super.dueRuns(now, limit: limit);
    } finally {
      active--;
    }
  }
}

class _GatedBroker extends InMemoryBroker {
  final entered = Completer<void>();
  final release = Completer<void>();
  bool blockPublish = false;
  int completedPublishes = 0;

  @override
  Future<void> publish(Envelope envelope, {RoutingInfo? routing}) async {
    if (blockPublish) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    await super.publish(envelope, routing: routing);
    completedPublishes++;
  }
}

class _RecordingLogDriver extends LogDriver {
  _RecordingLogDriver() : super('recording');

  final entries = <LogEntry>[];

  @override
  Future<void> log(LogEntry entry) async {
    entries.add(entry);
  }
}
