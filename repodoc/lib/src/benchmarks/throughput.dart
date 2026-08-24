import 'dart:async';

import 'package:stem/stem.dart';

import 'postgres_timing.dart';
import 'throughput_mode.dart';
import 'throughput_store.dart';

/// Parses benchmark durations such as `250ms`, `5s`, `2m`, or `1h`.
Duration parseThroughputDuration(String value) {
  final match = RegExp(
    r'^([0-9]+(?:\.[0-9]+)?)(ms|s|m|h)$',
  ).firstMatch(value.trim().toLowerCase());
  if (match == null) {
    throw ArgumentError(
      'Invalid benchmark duration "$value". Use values such as 5s or 2m.',
    );
  }
  final number = double.parse(match.group(1)!);
  final multiplier = switch (match.group(2)) {
    'ms' => Duration.microsecondsPerMillisecond,
    's' => Duration.microsecondsPerSecond,
    'm' => Duration.microsecondsPerMinute,
    'h' => Duration.microsecondsPerHour,
    _ => throw StateError('Unsupported duration unit.'),
  };
  final microseconds = (number * multiplier).round();
  if (microseconds <= 0) {
    throw ArgumentError('Benchmark duration must be positive.');
  }
  return Duration(microseconds: microseconds);
}

final class ThroughputBenchmark {
  const ThroughputBenchmark({
    required this.tasks,
    required this.warmupTasks,
    required this.concurrency,
    required this.store,
    this.mode = ThroughputMode.steadyState,
    this.measurementDuration,
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
  final ThroughputMode mode;
  final Duration? measurementDuration;
  final String? postgresUrl;
  final String? redisUrl;
  final String? sqlitePath;
  final bool collectPostgresTimings;
  final void Function(String message)? onStage;

  Future<Map<String, Object?>> run() async {
    if (measurementDuration != null && measurementDuration! <= Duration.zero) {
      throw ArgumentError('measurementDuration must be positive.');
    }
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
    var measurementClosed = false;
    var warmupCompletedTasks = 0;
    var measuredTasks = 0;
    var completedTasks = 0;
    void completeMeasuredIfReady() {
      if (measurementClosed &&
          completedTasks >= measuredTasks &&
          !completed.isCompleted) {
        completed.complete();
      }
    }

    final registry = InMemoryTaskRegistry()
      ..register(
        _ThroughputTask(
          onComplete: () {
            if (!measuring) {
              warmupCompletedTasks += 1;
              if (warmupCompletedTasks >= warmupTasks &&
                  !warmupCompleted.isCompleted) {
                warmupCompleted.complete();
              }
              return;
            }
            completedTasks += 1;
            completeMeasuredIfReady();
          },
        ),
      );
    final stem = Stem(broker: broker, registry: registry, backend: backend);
    Worker? worker;
    var workerStarted = false;

    Worker createWorker() => Worker(
      broker: executionBroker,
      registry: registry,
      backend: executionBackend,
      concurrency: concurrency,
      prefetchMultiplier: 1,
      heartbeatTransport: const NoopHeartbeatTransport(),
      consumerName: 'repodoc-throughput-worker',
      lifecycle: const WorkerLifecycleConfig(installSignalHandlers: false),
    );

    Future<void> startWorker() async {
      worker = createWorker();
      await worker!.start();
      workerStarted = true;
      stage('worker started');
    }

    Future<void> shutdownWorker() async {
      if (!workerStarted) return;
      stage('shutting down worker');
      await worker!.shutdown();
      workerStarted = false;
    }

    Future<void> runWarmup() async {
      if (warmupTasks <= 0) return;
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

    Future<void> enqueueMeasured() async {
      if (measurementDuration == null) {
        measuredTasks = tasks;
        await _enqueueTasks(
          stem,
          tasks,
          label: 'measured enqueue',
          stage: stage,
        );
        measurementClosed = true;
        completeMeasuredIfReady();
        return;
      }

      final duration = measurementDuration!;
      final window = Stopwatch()..start();
      var nextProgress = const Duration(seconds: 1);
      while (window.elapsed < duration) {
        final index = measuredTasks;
        measuredTasks += 1;
        await stem.enqueue('repodoc.benchmark.noop', args: {'index': index});
        if (window.elapsed >= nextProgress) {
          stage(
            'measured enqueue progress: $measuredTasks tasks in '
            '${window.elapsed.inMilliseconds}ms',
          );
          nextProgress += const Duration(seconds: 1);
        }
      }
      window.stop();
      measurementClosed = true;
      completeMeasuredIfReady();
    }

    try {
      if (mode == ThroughputMode.steadyState || warmupTasks > 0) {
        stage('starting worker');
        await startWorker();
        await runWarmup();
      }
      if (mode != ThroughputMode.steadyState) {
        await shutdownWorker();
      }

      measuring = true;
      final enqueue = Stopwatch()..start();
      if (mode == ThroughputMode.prefilledDrain) {
        stage('prefilling $tasks measured tasks');
        await enqueueMeasured();
        enqueue.stop();
        stage('prefill complete; starting worker drain');
        final total = Stopwatch()..start();
        await startWorker();
        await completed.future.timeout(const Duration(minutes: 2));
        final handlerEndToEnd = total.elapsed;
        stage('handlers complete; waiting for broker drain');
        await _waitForBrokerDrain(broker);
        total.stop();
        stage('broker drain complete');
        return _result(
          measuredTasks: measuredTasks,
          enqueue: enqueue.elapsed,
          handlerEndToEnd: handlerEndToEnd,
          total: total.elapsed,
          postgresTimings: postgresTimings,
        );
      }

      final total = Stopwatch()..start();
      stage('enqueueing $tasks measured tasks');
      await enqueueMeasured();
      enqueue.stop();
      if (mode == ThroughputMode.enqueueOnly) {
        stage('measured enqueue complete; purging unconsumed tasks');
        await _purgeBenchmarkQueue(broker);
        return _result(
          measuredTasks: measuredTasks,
          enqueue: enqueue.elapsed,
          postgresTimings: postgresTimings,
        );
      }

      stage('measured enqueue complete; waiting for handlers');
      await completed.future.timeout(const Duration(minutes: 2));
      final handlerEndToEnd = total.elapsed;
      stage('handlers complete; waiting for broker drain');
      await _waitForBrokerDrain(broker);
      total.stop();
      stage('broker drain complete');

      return _result(
        measuredTasks: measuredTasks,
        enqueue: enqueue.elapsed,
        handlerEndToEnd: handlerEndToEnd,
        total: total.elapsed,
        postgresTimings: postgresTimings,
      );
    } finally {
      try {
        await shutdownWorker();
      } finally {
        stage('closing store resources');
        try {
          await resources.close();
        } finally {
          stage('benchmark complete');
        }
      }
    }
  }

  Map<String, Object?> _result({
    required int measuredTasks,
    required Duration enqueue,
    Duration? handlerEndToEnd,
    Duration? total,
    PostgresTimingCollector? postgresTimings,
  }) {
    final result = <String, Object?>{
      'store': store.name,
      'mode': mode.name,
      'tasks': measuredTasks,
      'requested_tasks': tasks,
      'concurrency': concurrency,
      'measurement_duration_ms': measurementDuration?.inMicroseconds == null
          ? null
          : measurementDuration!.inMicroseconds / 1000,
      'enqueue_ms': enqueue.inMicroseconds / 1000,
      'handler_end_to_end_ms': handlerEndToEnd?.inMicroseconds == null
          ? null
          : handlerEndToEnd!.inMicroseconds / 1000,
      'end_to_end_ms': total?.inMicroseconds == null
          ? null
          : total!.inMicroseconds / 1000,
      'drain_ms': total == null
          ? null
          : mode == ThroughputMode.prefilledDrain
          ? total.inMicroseconds / 1000
          : (total.inMicroseconds - enqueue.inMicroseconds) / 1000,
      'store_drain_ms': handlerEndToEnd == null || total == null
          ? null
          : (total.inMicroseconds - handlerEndToEnd.inMicroseconds) / 1000,
      'enqueue_tasks_per_second': _rate(measuredTasks, enqueue),
      'handler_end_to_end_tasks_per_second': handlerEndToEnd == null
          ? null
          : _rate(measuredTasks, handlerEndToEnd),
      'end_to_end_tasks_per_second': total == null
          ? null
          : _rate(measuredTasks, total),
      if (postgresTimings != null) 'postgres_timings': postgresTimings.toJson(),
      if (postgresTimings != null)
        'postgres_queries': postgresTimings.queryJson(),
    };
    return result;
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

Future<void> _purgeBenchmarkQueue(QueueBroker broker) async {
  if (broker is Broker) {
    try {
      await broker.purge('default');
    } on UnsupportedError {
      // The benchmark namespace is unique, so adapters without purge support
      // are still safe to close after an enqueue-only run.
    }
  }
}

double _rate(int count, Duration duration) {
  final seconds = duration.inMicroseconds / Duration.microsecondsPerSecond;
  return seconds <= 0 ? 0 : count / seconds;
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
