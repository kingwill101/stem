import 'dart:async';

import 'package:stem/stem.dart';

import 'postgres_timing.dart';
import 'throughput_store.dart';

final class ThroughputBenchmark {
  const ThroughputBenchmark({
    required this.tasks,
    required this.warmupTasks,
    required this.concurrency,
    required this.store,
    this.postgresUrl,
    this.redisUrl,
    this.sqlitePath,
    this.collectPostgresTimings = false,
    this.onStage,
  });

  final int tasks;
  final int warmupTasks;
  final int concurrency;
  final ThroughputStore store;
  final String? postgresUrl;
  final String? redisUrl;
  final String? sqlitePath;
  final bool collectPostgresTimings;
  final void Function(String message)? onStage;

  Future<Map<String, Object?>> run() async {
    final elapsed = Stopwatch()..start();
    void stage(String message) {
      onStage?.call(
        '[throughput ${store.name} c$concurrency '
        '${elapsed.elapsedMilliseconds}ms] $message',
      );
    }

    final namespace =
        'repodoc-throughput-${store.name}-${DateTime.now().microsecondsSinceEpoch}';
    final postgresTimings =
        store == ThroughputStore.postgres && collectPostgresTimings
        ? PostgresTimingCollector()
        : null;
    stage('opening store resources');
    final resources = await openThroughputStore(
      store: store,
      namespace: namespace,
      postgresUrl: postgresUrl,
      redisUrl: redisUrl,
      sqlitePath: sqlitePath,
      postgresTimings: postgresTimings,
      log: stage,
    );
    stage('store resources ready');
    final broker = resources.broker;
    final backend = resources.backend;
    final executionBroker = resources.executionBroker;
    final executionBackend = resources.executionBackend;
    final completed = Completer<void>();
    final warmupCompleted = Completer<void>();
    var measuring = false;
    var warmupCompletedTasks = 0;
    var completedTasks = 0;
    final registry = InMemoryTaskRegistry()
      ..register(
        _ThroughputTask(
          onComplete: () {
            if (!measuring) {
              warmupCompletedTasks += 1;
              if (warmupCompletedTasks == warmupTasks &&
                  !warmupCompleted.isCompleted) {
                warmupCompleted.complete();
              }
              return;
            }
            completedTasks += 1;
            if (completedTasks == tasks && !completed.isCompleted) {
              completed.complete();
            }
          },
        ),
      );
    final stem = Stem(broker: broker, registry: registry, backend: backend);
    final worker = Worker(
      broker: executionBroker,
      registry: registry,
      backend: executionBackend,
      concurrency: concurrency,
      prefetchMultiplier: 1,
      heartbeatTransport: const NoopHeartbeatTransport(),
      consumerName: 'repodoc-throughput-worker',
      lifecycle: const WorkerLifecycleConfig(installSignalHandlers: false),
    );

    try {
      stage('starting worker');
      await worker.start();
      stage('worker started');
      if (warmupTasks > 0) {
        stage('enqueueing $warmupTasks warmup tasks');
        await _enqueueTasks(
          stem,
          warmupTasks,
          label: 'warmup enqueue',
          stage: stage,
        );
        stage('waiting for warmup handlers');
        await warmupCompleted.future.timeout(const Duration(minutes: 2));
        stage('warmup handlers complete; waiting for broker drain');
        await _waitForBrokerDrain(broker);
        stage('warmup broker drain complete');
      }

      measuring = true;
      final total = Stopwatch()..start();
      final enqueue = Stopwatch()..start();
      stage('enqueueing $tasks measured tasks');
      await _enqueueTasks(stem, tasks, label: 'measured enqueue', stage: stage);
      enqueue.stop();
      stage('measured enqueue complete; waiting for handlers');
      await completed.future.timeout(const Duration(minutes: 2));
      final handlerEndToEnd = total.elapsed;
      stage('handlers complete; waiting for broker drain');
      await _waitForBrokerDrain(broker);
      total.stop();
      stage('broker drain complete');

      return {
        'store': store.name,
        'tasks': tasks,
        'concurrency': concurrency,
        'enqueue_ms': enqueue.elapsedMicroseconds / 1000,
        'handler_end_to_end_ms': handlerEndToEnd.inMicroseconds / 1000,
        'end_to_end_ms': total.elapsedMicroseconds / 1000,
        'drain_ms':
            (total.elapsedMicroseconds - enqueue.elapsedMicroseconds) / 1000,
        'store_drain_ms':
            (total.elapsedMicroseconds - handlerEndToEnd.inMicroseconds) / 1000,
        'enqueue_tasks_per_second': _rate(tasks, enqueue.elapsed),
        'handler_end_to_end_tasks_per_second': _rate(tasks, handlerEndToEnd),
        'end_to_end_tasks_per_second': _rate(tasks, total.elapsed),
        if (postgresTimings != null)
          'postgres_timings': postgresTimings.toJson(),
        if (postgresTimings != null)
          'postgres_queries': postgresTimings.queryJson(),
      };
    } finally {
      stage('shutting down worker');
      await worker.shutdown();
      stage('closing store resources');
      await resources.close();
      stage('benchmark complete');
    }
  }
}

Future<void> _enqueueTasks(
  Stem stem,
  int count, {
  required String label,
  required void Function(String message) stage,
}) async {
  final progressEvery = count < 20 ? 1 : (count / 20).ceil();
  for (var index = 0; index < count; index++) {
    await stem.enqueue('repodoc.benchmark.noop', args: {'index': index});
    final completed = index + 1;
    if (completed == count || completed % progressEvery == 0) {
      stage('$label progress: $completed/$count');
    }
  }
}

Future<void> _waitForBrokerDrain(QueueBroker broker) async {
  final inspectable = broker is InspectableBroker ? broker : null;
  if (inspectable == null) return;

  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (DateTime.now().isBefore(deadline)) {
    final pending = await inspectable.pendingCount('default');
    final inflight = await inspectable.inflightCount('default');
    if ((pending ?? 0) == 0 && (inflight ?? 0) == 0) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw TimeoutException(
    'Timed out waiting for the benchmark broker to drain.',
  );
}

double _rate(int count, Duration duration) {
  final seconds = duration.inMicroseconds / Duration.microsecondsPerSecond;
  return seconds == 0 ? double.infinity : count / seconds;
}

final class _ThroughputTask extends TaskHandler<void> {
  _ThroughputTask({required this.onComplete});

  final void Function() onComplete;

  @override
  String get name => 'repodoc.benchmark.noop';

  @override
  TaskOptions get options => const TaskOptions();

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    onComplete();
  }
}
