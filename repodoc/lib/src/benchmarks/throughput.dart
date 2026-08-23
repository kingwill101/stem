import 'dart:async';

import 'package:stem/memory.dart';
import 'package:stem/stem.dart';

final class ThroughputBenchmark {
  const ThroughputBenchmark({
    required this.tasks,
    required this.warmupTasks,
    required this.concurrency,
  });

  final int tasks;
  final int warmupTasks;
  final int concurrency;

  Future<Map<String, Object?>> run() async {
    final broker = InMemoryBroker();
    final backend = InMemoryResultBackend();
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
      broker: broker,
      registry: registry,
      backend: backend,
      concurrency: concurrency,
      prefetchMultiplier: 1,
      heartbeatTransport: const NoopHeartbeatTransport(),
      consumerName: 'repodoc-throughput-worker',
      lifecycle: const WorkerLifecycleConfig(installSignalHandlers: false),
    );

    try {
      await worker.start();
      if (warmupTasks > 0) {
        for (var index = 0; index < warmupTasks; index++) {
          await stem.enqueue('repodoc.benchmark.noop', args: {'index': index});
        }
        await warmupCompleted.future.timeout(const Duration(minutes: 2));
      }

      measuring = true;
      final total = Stopwatch()..start();
      final enqueue = Stopwatch()..start();
      for (var index = 0; index < tasks; index++) {
        await stem.enqueue('repodoc.benchmark.noop', args: {'index': index});
      }
      enqueue.stop();
      await completed.future.timeout(const Duration(minutes: 2));
      total.stop();

      return {
        'tasks': tasks,
        'concurrency': concurrency,
        'enqueue_ms': enqueue.elapsedMicroseconds / 1000,
        'end_to_end_ms': total.elapsedMicroseconds / 1000,
        'drain_ms':
            (total.elapsedMicroseconds - enqueue.elapsedMicroseconds) / 1000,
        'enqueue_tasks_per_second': _rate(tasks, enqueue.elapsed),
        'end_to_end_tasks_per_second': _rate(tasks, total.elapsed),
      };
    } finally {
      await worker.shutdown();
      await stem.close();
    }
  }
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
