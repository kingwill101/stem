import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:stem/memory.dart';
import 'package:stem/stem.dart';

import 'profile_support.dart';

/// Runs one deterministic worker-job profile.
///
/// This workload is deliberately separate from the throughput regression
/// benchmark. It records per-task lifecycle timings, supports both execution
/// modes, and can hold the process open for a VM-service/DevTools session.
Future<void> main(List<String> args) async {
  if (args.contains('--help')) {
    _printUsage();
    return;
  }

  final config = _ProfileConfig.fromArgs(args);
  final runStarted = DateTime.now().toUtc();
  final rssBefore = ProcessInfo.currentRss;
  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();
  final handler = _buildHandler(config);
  final registry = InMemoryTaskRegistry()..register(handler);
  final stem = Stem(broker: broker, registry: registry, backend: backend);
  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    concurrency: config.concurrency,
    prefetchMultiplier: 1,
    heartbeatTransport: const NoopHeartbeatTransport(),
    consumerName: 'stem-job-profile-worker',
    lifecycle: const WorkerLifecycleConfig(installSignalHandlers: false),
  );

  try {
    await worker.start();
    await _runBatch(
      stem,
      backend,
      config,
      tasks: config.warmup,
      measured: false,
    );

    final totalTimer = Stopwatch()..start();
    final measuredBatch = await _enqueueBatch(
      stem,
      backend,
      config,
      tasks: config.tasks,
      measured: true,
    );
    final measuredStatuses = await _awaitBatch(measuredBatch.waiters);
    totalTimer.stop();

    final runFinished = DateTime.now().toUtc();
    final result = <String, Object?>{
      'schemaVersion': 1,
      'kind': 'stem.job.profile',
      'startedAtUtc': runStarted.toIso8601String(),
      'finishedAtUtc': runFinished.toIso8601String(),
      'dartVersion': Platform.version,
      'operatingSystem': Platform.operatingSystem,
      'processorCount': Platform.numberOfProcessors,
      'tasks': config.tasks,
      'warmupTasks': config.warmup,
      'concurrency': config.concurrency,
      'executionMode': config.mode.name,
      'workload': config.workload.name,
      'workUnits': config.workUnits,
      'enqueueMs': measuredBatch.enqueueElapsed.inMicroseconds / 1000,
      'endToEndMs': totalTimer.elapsedMicroseconds / 1000,
      'enqueueTasksPerSecond': _rate(
        config.tasks,
        measuredBatch.enqueueElapsed,
      ),
      'endToEndTasksPerSecond': _rate(config.tasks, totalTimer.elapsed),
      'rssBeforeBytes': rssBefore,
      'rssAfterBytes': ProcessInfo.currentRss,
      'queueLatencyMs': _timingStats(measuredStatuses.map(_queueLatencyMs)),
      'executionLatencyMs': _timingStats(
        measuredStatuses.map(_executionLatencyMs),
      ),
      'taskEndToEndLatencyMs': _timingStats(
        measuredStatuses.map(_taskEndToEndLatencyMs),
      ),
    };

    final encoded = jsonEncode(result);
    final output = profileStringOption(args, '--output');
    if (output != null) {
      final file = File(output);
      await file.parent.create(recursive: true);
      await file.writeAsString('$encoded\n');
    }
    stdout.writeln(encoded);
    await stdout.flush();

    if (config.holdSeconds > 0) {
      await Future<void>.delayed(Duration(seconds: config.holdSeconds));
    }
  } finally {
    await worker.shutdown();
    await broker.close();
    await backend.close();
  }
}

TaskHandler<Object?> _buildHandler(_ProfileConfig config) {
  final entrypoint = config.workload == _ProfileWorkload.cpu
      ? _cpuProfileEntrypoint
      : _noopProfileEntrypoint;
  if (config.mode == TaskExecutionMode.inline) {
    return FunctionTaskHandler<Object?>.inline(
      name: 'profile.job',
      entrypoint: entrypoint,
    );
  }
  return FunctionTaskHandler<Object?>(
    name: 'profile.job',
    entrypoint: entrypoint,
  );
}

Future<void> _runBatch(
  Stem stem,
  ResultBackend backend,
  _ProfileConfig config, {
  required int tasks,
  required bool measured,
}) async {
  final batch = await _enqueueBatch(
    stem,
    backend,
    config,
    tasks: tasks,
    measured: measured,
  );
  await _awaitBatch(batch.waiters);
}

Future<_ProfileBatch> _enqueueBatch(
  Stem stem,
  ResultBackend backend,
  _ProfileConfig config, {
  required int tasks,
  required bool measured,
}) async {
  if (tasks == 0) {
    return const _ProfileBatch(waiters: [], enqueueElapsed: Duration.zero);
  }

  final waiters = <Future<TaskStatus>>[];
  final enqueueTimer = Stopwatch()..start();
  for (var index = 0; index < tasks; index++) {
    final id = generateEnvelopeId();
    final enqueuedAt = DateTime.now().toUtc().toIso8601String();
    waiters.add(_watchTerminal(backend, id));
    final returnedId = await stem.enqueue(
      'profile.job',
      args: {'index': index, 'workUnits': config.workUnits},
      meta: {if (measured) 'profileEnqueuedAt': enqueuedAt},
      enqueueOptions: TaskEnqueueOptions(taskId: id),
    );
    if (returnedId != id) {
      throw StateError(
        'Profile task ID mismatch: expected $id, got $returnedId',
      );
    }
  }
  enqueueTimer.stop();
  return _ProfileBatch(waiters: waiters, enqueueElapsed: enqueueTimer.elapsed);
}

Future<List<TaskStatus>> _awaitBatch(List<Future<TaskStatus>> waiters) async {
  final statuses = await Future.wait(
    waiters,
  ).timeout(const Duration(minutes: 10));
  for (final status in statuses) {
    if (status.state != TaskState.succeeded) {
      throw StateError(
        'Profile task ${status.id} ended in ${status.state.name}: '
        '${status.error?.message ?? 'unknown error'}',
      );
    }
  }
  return statuses;
}

Future<TaskStatus> _watchTerminal(ResultBackend backend, String taskId) {
  final completer = Completer<TaskStatus>();
  late StreamSubscription<TaskStatus> subscription;
  subscription = backend
      .watch(taskId)
      .listen(
        (status) {
          if (!status.state.isTerminal || completer.isCompleted) return;
          completer.complete(status);
          unawaited(subscription.cancel());
        },
        onError: (Object error, StackTrace stack) {
          if (!completer.isCompleted) completer.completeError(error, stack);
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.completeError(
              StateError('Profile status stream closed before task completed.'),
            );
          }
        },
      );
  return completer.future;
}

FutureOr<Object?> _noopProfileEntrypoint(
  TaskInvocationContext _,
  Map<String, Object?> args,
) {
  return args['index'];
}

FutureOr<Object?> _cpuProfileEntrypoint(
  TaskInvocationContext _,
  Map<String, Object?> args,
) {
  final index = (args['index']! as num).toInt();
  final workUnits = (args['workUnits']! as num).toInt();
  var digest = sha256.convert(<int>[index & 0xff, index >> 8]);
  for (var round = 0; round < workUnits; round++) {
    digest = sha256.convert(<int>[...digest.bytes, round & 0xff, index & 0xff]);
  }
  return digest.toString();
}

double _rate(int count, Duration duration) {
  final seconds = duration.inMicroseconds / Duration.microsecondsPerSecond;
  return seconds <= 0 ? 0 : count / seconds;
}

double? _queueLatencyMs(TaskStatus status) {
  return _differenceMs(
    status.meta['profileEnqueuedAt'],
    status.meta['startedAt'],
  );
}

double? _executionLatencyMs(TaskStatus status) {
  return _differenceMs(status.meta['startedAt'], status.meta['completedAt']);
}

double? _taskEndToEndLatencyMs(TaskStatus status) {
  return _differenceMs(
    status.meta['profileEnqueuedAt'],
    status.meta['completedAt'],
  );
}

double? _differenceMs(Object? start, Object? end) {
  if (start is! String || end is! String) return null;
  final startAt = DateTime.tryParse(start);
  final endAt = DateTime.tryParse(end);
  if (startAt == null || endAt == null) return null;
  return endAt.difference(startAt).inMicroseconds / 1000;
}

Map<String, Object?> _timingStats(Iterable<double?> values) {
  final sorted = values.whereType<double>().toList()..sort();
  if (sorted.isEmpty) return {'count': 0};
  final sum = sorted.fold<double>(0, (total, value) => total + value);
  return {
    'count': sorted.length,
    'min': sorted.first,
    'median': profilePercentile(sorted, 0.5),
    'p95': profilePercentile(sorted, 0.95),
    'max': sorted.last,
    'mean': sum / sorted.length,
  };
}

void _printUsage() {
  stdout.writeln('''
Stem job profile

Runs a deterministic in-memory worker workload and emits one JSON sample.

Options:
  --tasks <n>              Measured task count (default: 5000)
  --warmup <n>             Warmup task count (default: 500)
  --concurrency <n>        Worker concurrency (default: 4)
  --mode inline|isolate    Handler execution mode (default: isolate)
  --workload noop|cpu      Handler workload (default: noop)
  --work-units <n>         CPU hash rounds per task (default: 100)
  --hold-seconds <n>       Keep the VM alive after output (default: 0)
  --output <path>          Also write JSON to this file
''');
}

enum _ProfileWorkload { noop, cpu }

final class _ProfileBatch {
  const _ProfileBatch({required this.waiters, required this.enqueueElapsed});

  final List<Future<TaskStatus>> waiters;
  final Duration enqueueElapsed;
}

final class _ProfileConfig {
  const _ProfileConfig({
    required this.tasks,
    required this.warmup,
    required this.concurrency,
    required this.mode,
    required this.workload,
    required this.workUnits,
    required this.holdSeconds,
  });

  factory _ProfileConfig.fromArgs(List<String> args) {
    final tasks = profileIntOption(args, '--tasks', 5000);
    final warmup = profileIntOption(args, '--warmup', 500);
    final concurrency = profileIntOption(args, '--concurrency', 4);
    final workUnits = profileIntOption(args, '--work-units', 100);
    final holdSeconds = profileIntOption(args, '--hold-seconds', 0);
    final mode = profileStringOption(args, '--mode') ?? 'isolate';
    final workload = profileStringOption(args, '--workload') ?? 'noop';

    if (tasks <= 0 || warmup < 0 || concurrency <= 0 || workUnits < 0) {
      throw ArgumentError(
        'tasks/concurrency must be positive; warmup/work-units cannot be '
        'negative.',
      );
    }
    if (holdSeconds < 0) {
      throw ArgumentError.value(holdSeconds, '--hold-seconds');
    }

    final resolvedMode = _parseExecutionMode(mode);
    final resolvedWorkload = _parseWorkload(workload);
    return _ProfileConfig(
      tasks: tasks,
      warmup: warmup,
      concurrency: concurrency,
      mode: resolvedMode,
      workload: resolvedWorkload,
      workUnits: workUnits,
      holdSeconds: holdSeconds,
    );
  }

  final int tasks;
  final int warmup;
  final int concurrency;
  final TaskExecutionMode mode;
  final _ProfileWorkload workload;
  final int workUnits;
  final int holdSeconds;

  static TaskExecutionMode _parseExecutionMode(String value) {
    for (final mode in TaskExecutionMode.values) {
      if (mode.name == value) return mode;
    }
    throw ArgumentError(
      'Invalid --mode "$value". Expected one of: '
      '${TaskExecutionMode.values.map((mode) => mode.name).join(', ')}.',
    );
  }

  static _ProfileWorkload _parseWorkload(String value) {
    for (final workload in _ProfileWorkload.values) {
      if (workload.name == value) return workload;
    }
    throw ArgumentError(
      'Invalid --workload "$value". Expected one of: '
      '${_ProfileWorkload.values.map((workload) => workload.name).join(', ')}.',
    );
  }
}
