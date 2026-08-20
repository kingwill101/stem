import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_sqlite/stem_sqlite.dart';

Future<void> main(List<String> args) async {
  final tasks = _intOption(args, '--tasks') ?? 1000;
  final concurrency = _intOption(args, '--concurrency') ?? 4;
  final checkBaseline = args.contains('--check-baseline');
  if (tasks <= 0 || concurrency <= 0) {
    throw ArgumentError('Tasks and concurrency must be positive.');
  }

  final directory = await Directory.systemTemp.createTemp(
    'stem-sqlite-throughput-',
  );
  final file = File('${directory.path}/stem.db');
  final broker = await SqliteBroker.open(
    file,
    namespace: 'benchmark',
    pollInterval: const Duration(milliseconds: 5),
    sweeperInterval: const Duration(hours: 1),
  );
  final backend = await SqliteResultBackend.open(
    file,
    namespace: 'benchmark',
    cleanupInterval: const Duration(hours: 1),
  );
  final completed = Completer<void>();
  var completedTasks = 0;
  final registry = InMemoryTaskRegistry()
    ..register(
      _BenchmarkTask(
        onComplete: () {
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
    consumerName: 'sqlite-benchmark-worker',
    lifecycle: const WorkerLifecycleConfig(installSignalHandlers: false),
  );

  try {
    await worker.start();
    final total = Stopwatch()..start();
    final enqueue = Stopwatch()..start();
    for (var index = 0; index < tasks; index++) {
      await stem.enqueue('benchmark.sqlite.noop', args: {'index': index});
    }
    enqueue.stop();

    await completed.future.timeout(const Duration(minutes: 2));
    total.stop();
    final result = <String, Object?>{
      'adapter': 'sqlite',
      'tasks': tasks,
      'concurrency': concurrency,
      'enqueue_ms': enqueue.elapsedMicroseconds / 1000,
      'end_to_end_ms': total.elapsedMicroseconds / 1000,
      'enqueue_tasks_per_second': _rate(tasks, enqueue.elapsed),
      'end_to_end_tasks_per_second': _rate(tasks, total.elapsed),
    };
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
    if (checkBaseline) _checkBaseline(result);
    await stdout.flush();
  } finally {
    await worker.shutdown();
    await backend.close();
    await broker.close();
    await directory.delete(recursive: true);
  }
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
  final baselineFile = File('benchmark/sqlite_throughput_baseline.json');
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
      'SQLite throughput regressed: measured $measured tasks/s, '
      'minimum $minimum tasks/s.',
    );
  }
}

final class _BenchmarkTask extends TaskHandler<void> {
  _BenchmarkTask({required this.onComplete});

  final void Function() onComplete;

  @override
  String get name => 'benchmark.sqlite.noop';

  @override
  TaskOptions get options => const TaskOptions();

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    onComplete();
  }
}
