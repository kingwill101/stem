import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:stem/memory.dart';
import 'package:stem/stem.dart';

Future<void> main(List<String> args) async {
  final tasks = _intOption(args, '--tasks') ?? 5000;
  final concurrency = _intOption(args, '--concurrency') ?? 8;
  final warmupTasks = _intOption(args, '--warmup') ?? 250;
  final checkBaseline = args.contains('--check-baseline');

  if (tasks <= 0 || concurrency <= 0 || warmupTasks < 0) {
    throw ArgumentError(
      'Tasks and concurrency must be positive; warmup cannot be negative.',
    );
  }

  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();
  final completed = Completer<void>();
  final warmupCompleted = Completer<void>();
  var measuring = false;
  var warmupCompletedTasks = 0;
  var completedTasks = 0;
  final registry = InMemoryTaskRegistry()
    ..register(
      _BenchmarkTask(
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
    consumerName: 'benchmark-worker',
    lifecycle: const WorkerLifecycleConfig(installSignalHandlers: false),
  );

  await worker.start();
  if (warmupTasks > 0) {
    for (var index = 0; index < warmupTasks; index++) {
      await stem.enqueue('benchmark.noop', args: {'index': index});
    }
    await warmupCompleted.future.timeout(const Duration(minutes: 2));
  }
  measuring = true;
  final total = Stopwatch()..start();
  final enqueue = Stopwatch()..start();
  for (var index = 0; index < tasks; index++) {
    await stem.enqueue('benchmark.noop', args: {'index': index});
  }
  enqueue.stop();

  await completed.future.timeout(const Duration(minutes: 2));
  total.stop();
  await worker.shutdown();
  broker.dispose();

  final result = <String, Object?>{
    'tasks': tasks,
    'concurrency': concurrency,
    'enqueue_ms': enqueue.elapsedMicroseconds / 1000,
    'end_to_end_ms': total.elapsedMicroseconds / 1000,
    'enqueue_tasks_per_second': _rate(tasks, enqueue.elapsed),
    'end_to_end_tasks_per_second': _rate(tasks, total.elapsed),
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));

  if (checkBaseline) {
    _checkBaseline(result);
  }
  await stdout.flush();
  // The benchmark owns a short-lived process and has already disposed all
  // runtime resources. Exit explicitly so a broker/stream implementation that
  // leaves a non-terminal listener cannot make the benchmark appear hung.
  exit(0);
}

double _rate(int count, Duration duration) {
  final seconds = duration.inMicroseconds / Duration.microsecondsPerSecond;
  return seconds == 0 ? double.infinity : count / seconds;
}

int? _intOption(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) return null;
  return int.tryParse(args[index + 1]);
}

void _checkBaseline(Map<String, Object?> result) {
  final baselineFile = File('benchmark/stem_throughput_baseline.json');
  if (!baselineFile.existsSync()) {
    throw StateError('Missing benchmark baseline: ${baselineFile.path}');
  }
  final baseline = jsonDecode(baselineFile.readAsStringSync());
  if (baseline is! Map<String, dynamic>) {
    throw StateError('Benchmark baseline must be a JSON object.');
  }
  final minimum = baseline['minimum_end_to_end_tasks_per_second'];
  final measured = result['end_to_end_tasks_per_second'];
  if (minimum is! num || measured is! num || measured < minimum) {
    throw StateError(
      'End-to-end throughput regressed: measured $measured tasks/s, '
      'minimum $minimum tasks/s.',
    );
  }
}

final class _BenchmarkTask extends TaskHandler<void> {
  _BenchmarkTask({required this.onComplete});

  final void Function() onComplete;

  @override
  String get name => 'benchmark.noop';

  @override
  TaskOptions get options => const TaskOptions();

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    onComplete();
  }
}
