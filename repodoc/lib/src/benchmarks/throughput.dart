import 'dart:async';

import 'package:stem/stem.dart';

import 'postgres_timing.dart';
import 'throughput_mode.dart';
import 'throughput_scenario.dart';
import 'throughput_statistics.dart';
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
    this.scenario = ThroughputScenario.success,
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
  final ThroughputScenario scenario;
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
    final warmupCompleted = Completer<void>();
    var measuring = false;
    var warmupCompletedTasks = 0;
    var measuredTasks = 0;
    final taskLatencies = <double>[];
    final measuredWaiters = <Future<_ObservedTerminal>>[];

    final registry = InMemoryTaskRegistry()
      ..register(
        _ThroughputTask(
          scenario: scenario,
          onTerminal: () {
            if (!measuring) {
              warmupCompletedTasks += 1;
              if (warmupCompletedTasks >= warmupTasks &&
                  !warmupCompleted.isCompleted) {
                warmupCompleted.complete();
              }
            }
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
        backend,
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
          backend,
          tasks,
          label: 'measured enqueue',
          stage: stage,
          terminalWaiters: measuredWaiters,
        );
        return;
      }

      final duration = measurementDuration!;
      final window = Stopwatch()..start();
      var nextProgress = const Duration(seconds: 1);
      while (window.elapsed < duration) {
        final index = measuredTasks;
        measuredTasks += 1;
        final enqueuedAtMicros = DateTime.now().microsecondsSinceEpoch;
        final taskId = generateEnvelopeId();
        measuredWaiters.add(_watchTerminal(backend, taskId));
        await stem.enqueue(
          'repodoc.benchmark.noop',
          args: {'index': index},
          meta: {'enqueuedAtMicros': enqueuedAtMicros},
          enqueueOptions: TaskEnqueueOptions(taskId: taskId),
        );
        if (window.elapsed >= nextProgress) {
          stage(
            'measured enqueue progress: $measuredTasks tasks in '
            '${window.elapsed.inMilliseconds}ms',
          );
          nextProgress += const Duration(seconds: 1);
        }
      }
      window.stop();
    }

    Future<void> awaitMeasuredStatuses() async {
      final statuses = await Future.wait(
        measuredWaiters,
      ).timeout(const Duration(minutes: 2));
      for (final terminal in statuses) {
        final latency = _observedTaskLatencyMs(terminal);
        if (latency != null) taskLatencies.add(latency);
      }
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
        await awaitMeasuredStatuses();
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
          taskLatencies: taskLatencies,
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
          taskLatencies: taskLatencies,
          postgresTimings: postgresTimings,
        );
      }

      stage('measured enqueue complete; waiting for handlers');
      await awaitMeasuredStatuses();
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
        taskLatencies: taskLatencies,
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
    required List<double> taskLatencies,
    PostgresTimingCollector? postgresTimings,
  }) {
    final latency = ThroughputStatistics.summarize(taskLatencies);
    final result = <String, Object?>{
      'store': store.name,
      'mode': mode.name,
      'scenario': scenario.name,
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
      'task_latency_p95_ms': latency['p95'],
      'task_latency_ms': latency,
      if (postgresTimings != null) 'postgres_timings': postgresTimings.toJson(),
      if (postgresTimings != null)
        'postgres_queries': postgresTimings.queryJson(),
    };
    return result;
  }
}

Future<void> _enqueueTasks(
  Stem stem,
  ResultBackend backend,
  int count, {
  required String label,
  required void Function(String message) stage,
  List<Future<_ObservedTerminal>>? terminalWaiters,
}) async {
  final progressEvery = count < 20 ? 1 : (count / 20).ceil();
  for (var index = 0; index < count; index++) {
    final enqueuedAtMicros = DateTime.now().microsecondsSinceEpoch;
    final taskId = generateEnvelopeId();
    if (terminalWaiters != null) {
      terminalWaiters.add(_watchTerminal(backend, taskId));
    }
    await stem.enqueue(
      'repodoc.benchmark.noop',
      args: {'index': index},
      meta: {'enqueuedAtMicros': enqueuedAtMicros},
      enqueueOptions: TaskEnqueueOptions(taskId: taskId),
    );
    final completed = index + 1;
    if (completed == count || completed % progressEvery == 0) {
      stage('$label progress: $completed/$count');
    }
  }
}

final class _ObservedTerminal {
  const _ObservedTerminal(this.status, this.observedAtMicros);

  final TaskStatus status;
  final int observedAtMicros;
}

Future<_ObservedTerminal> _watchTerminal(ResultBackend backend, String taskId) {
  final completer = Completer<_ObservedTerminal>();
  late StreamSubscription<TaskStatus> subscription;
  subscription = backend
      .watch(taskId)
      .listen(
        (status) {
          if (!status.state.isTerminal || completer.isCompleted) return;
          completer.complete(
            _ObservedTerminal(status, DateTime.now().microsecondsSinceEpoch),
          );
          unawaited(subscription.cancel());
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!completer.isCompleted)
            completer.completeError(error, stackTrace);
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.completeError(
              StateError('Benchmark status stream closed before completion.'),
            );
          }
        },
      );
  return completer.future;
}

double? _observedTaskLatencyMs(_ObservedTerminal terminal) {
  final enqueuedAt = (terminal.status.meta['enqueuedAtMicros'] as num?)
      ?.toInt();
  if (enqueuedAt == null) return null;
  return (terminal.observedAtMicros - enqueuedAt) /
      Duration.microsecondsPerMillisecond;
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
  _ThroughputTask({required this.scenario, required this.onTerminal});

  final ThroughputScenario scenario;
  final void Function() onTerminal;

  @override
  String get name => 'repodoc.benchmark.noop';

  @override
  TaskOptions get options => const TaskOptions();

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    void recordTerminal() => onTerminal();

    switch (scenario) {
      case ThroughputScenario.success:
        recordTerminal();
      case ThroughputScenario.retry:
        if (context.attempt == 0) {
          await context.retry(
            countdown: Duration.zero,
            maxRetries: 1,
            retryPolicy: const TaskRetryPolicy(
              defaultDelay: Duration.zero,
              jitter: false,
              maxRetries: 1,
            ),
          );
          return;
        }
        recordTerminal();
      case ThroughputScenario.deadLetter:
        recordTerminal();
        throw StateError('repodoc benchmark dead-letter scenario');
      case ThroughputScenario.lease:
        await context.extendLease(const Duration(seconds: 1));
        recordTerminal();
    }
  }
}
