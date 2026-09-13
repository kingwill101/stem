import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:stem/stem.dart';

import 'profile_support.dart';

/// Profiles the standard in-memory Stem workflow runtime, not a prototype host.
///
/// TimelineTask markers are Dart VM timeline events, not
/// devtools_region_profiler regions. Enable the Dart timeline stream when
/// recording them. Per-run public-API result polling overhead is included.
Future<void> main(List<String> arguments) async {
  late WorkflowProfileConfig config;
  try {
    if (arguments.length == 1 &&
        (arguments.single == '--help' || arguments.single == '-h')) {
      stdout.writeln(WorkflowProfileConfig.usage);
      return;
    }
    config = WorkflowProfileConfig.fromArgs(arguments);
  } on FormatException catch (error) {
    stderr.writeln('${error.message}\n${WorkflowProfileConfig.usage}');
    exitCode = 64;
    return;
  }

  try {
    final result = await runWorkflowProfile(config);
    final encoded = '${jsonEncode(result)}\n';
    if (config.output case final output?) {
      final file = File(output);
      await file.parent.create(recursive: true);
      await file.writeAsString(encoded);
    }
    stdout.write(encoded);
    await stdout.flush();
    // Keep only the VM alive for capture retrieval: the app is already closed.
    if (config.holdSeconds > 0) {
      await Future<void>.delayed(Duration(seconds: config.holdSeconds));
    }
  } catch (error, stack) {
    stderr.writeln('Workflow profile failed: $error\n$stack');
    exitCode = 1;
  }
}

/// Validated command-line configuration.
class WorkflowProfileConfig {
  WorkflowProfileConfig._({
    required this.runs,
    required this.warmup,
    required this.steps,
    required this.concurrency,
    required this.timeoutSeconds,
    required this.holdSeconds,
    required this.output,
  });

  /// Parses and validates options without starting any runtime resources.
  factory WorkflowProfileConfig.fromArgs(List<String> arguments) {
    const defaults = {
      '--runs': '100',
      '--tasks': '100',
      '--warmup': '10',
      '--steps': '5',
      '--concurrency': '1',
      '--timeout-seconds': '120',
      '--hold-seconds': '0',
      '--output': '',
    };
    final seen = <String>{};
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      final name = argument.split('=').first;
      if (!defaults.containsKey(name)) {
        throw FormatException('Unknown option or argument: $argument');
      }
      if (!seen.add(name)) {
        throw FormatException('Duplicate option: $name');
      }
      if (!argument.contains('=')) {
        index++;
        if (index >= arguments.length || arguments[index].startsWith('--')) {
          throw FormatException('Missing value for $name.');
        }
      }
    }

    int integer(String name, {int minimum = 1}) {
      final option = '--$name';
      final value = int.tryParse(
        profileStringOption(arguments, option) ?? defaults[option]!,
      );
      if (value == null || value < minimum || value > 1000000000) {
        throw FormatException(
          '--$name must be an integer from $minimum to 1000000000.',
        );
      }
      return value;
    }

    if (seen.contains('--runs') && seen.contains('--tasks')) {
      throw const FormatException('Use either --runs or --tasks, not both.');
    }
    final output = profileStringOption(arguments, '--output');
    if (output != null && output.trim().isEmpty) {
      throw const FormatException('--output must be a nonempty file path.');
    }
    return WorkflowProfileConfig._(
      runs: integer(seen.contains('--tasks') ? 'tasks' : 'runs'),
      warmup: integer('warmup', minimum: 0),
      steps: integer('steps'),
      concurrency: integer('concurrency'),
      timeoutSeconds: integer('timeout-seconds'),
      holdSeconds: integer('hold-seconds', minimum: 0),
      output: output,
    );
  }

  static const usage = '''
dart run benchmark/stem_workflow_profile.dart [options]
  --runs N             Measured workflow runs (default: 100).
  --tasks N            Alias for --runs, not worker task count.
  --warmup N           Warmup workflow runs (default: 10; zero allowed).
  --steps N            Sequential checkpoints per run (default: 5).
  --concurrency N      Worker concurrency (default: 1).
  --timeout-seconds N  Completion deadline per phase (default: 120).
  --hold-seconds N     Keep VM alive after cleanup/output (default: 0).
  --output PATH        Also write JSON to a file.
  --help, -h          Show this help (used alone).
Options accept --name value or --name=value; duplicates are rejected.
TimelineTask markers use the Dart VM timeline, not devtools_region_profiler
regions. Per-run result polling (100 ms) is included in measured time.''';

  final int runs;
  final int warmup;
  final int steps;
  final int concurrency;
  final int timeoutSeconds;
  final int holdSeconds;
  final String? output;
}

/// Runs warmup and measured phases with a completion barrier between them.
///
/// No workflow sleeps, events, or synthetic timers are added to the workload.
/// Runtime maintenance and the public result waiter's polling still use timers.
/// Warmup and measured runs share an app/store, as in a long-lived process.
Future<Map<String, Object?>> runWorkflowProfile(
  WorkflowProfileConfig config,
) async {
  var checkpointsExecuted = 0;
  final script = WorkflowScript<int>(
    name: 'profile.workflow.checkpoints',
    run: (context) async {
      var value = 0;
      for (var step = 0; step < config.steps; step++) {
        final next = value + step + 1;
        value = await context.step<int>('checkpoint.$step', (_) {
          checkpointsExecuted++;
          return next;
        });
      }
      return value;
    },
  );
  final app = await StemWorkflowApp.inMemory(
    scripts: [script],
    workerConfig: StemWorkerConfig(
      queue: 'workflow',
      concurrency: config.concurrency,
      prefetchMultiplier: 1,
      consumerName: 'stem-workflow-profile-worker',
      heartbeatTransport: const NoopHeartbeatTransport(),
      lifecycle: const WorkerLifecycleConfig(installSignalHandlers: false),
    ),
  );
  try {
    await app.start();
    final warmup = await _runPhase(
      'warmup',
      config.warmup,
      config,
      app,
      script,
      () => checkpointsExecuted,
    );
    final measured = await _runPhase(
      'measured',
      config.runs,
      config,
      app,
      script,
      () => checkpointsExecuted,
    );
    return {
      'schemaVersion': 1,
      'kind': 'stem.workflow.profile',
      'runtime': 'StemWorkflowApp.inMemory',
      'workload': 'sequential-script-checkpoints',
      'dartVersion': Platform.version,
      'operatingSystem': Platform.operatingSystem,
      'processorCount': Platform.numberOfProcessors,
      'runs': config.runs,
      'warmupRuns': config.warmup,
      'stepsPerRun': config.steps,
      'concurrency': config.concurrency,
      'prefetchMultiplier': 1,
      'resultPollIntervalMs': 100,
      'timeoutSeconds': config.timeoutSeconds,
      'timelineMarkers': 'Dart VM TimelineTask; not devtools_region_profiler',
      'warmup': warmup,
      'measured': measured,
    };
  } finally {
    // The in-memory bootstrap owns worker, broker, backend, store, and event bus.
    await app.close();
  }
}

Future<Map<String, Object?>> _runPhase(
  String phase,
  int runs,
  WorkflowProfileConfig config,
  StemWorkflowApp app,
  WorkflowScript<int> script,
  int Function() checkpointsExecuted,
) async {
  final marker = TimelineTask()..start('stem.workflow.profile.$phase');
  final startedAt = DateTime.now().toUtc();
  final startedTimelineMicros = Timeline.now;
  final timer = Stopwatch()..start();
  final initialCheckpoints = checkpointsExecuted();
  final timeout = Duration(seconds: config.timeoutSeconds);
  Duration remaining() {
    final remaining = timeout - timer.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException('$phase completion deadline exceeded', timeout);
    }
    return remaining;
  }

  var succeeded = false;
  try {
    final ids = <String>[];
    Future<String> startWithinDeadline() async {
      final budget = remaining();
      final submission = script.start(app);
      var deadlineObserved = false;
      try {
        return await submission.timeout(
          budget,
          onTimeout: () {
            deadlineObserved = true;
            throw TimeoutException('$phase submission deadline exceeded', timeout);
          },
        );
      } finally {
        if (deadlineObserved) {
          // Future.timeout only stops waiting; it does not cancel the
          // submission. Join it before this phase can fail and app.close can
          // begin, so an outstanding write never uses a closed store.
          await submission;
        }
      }
    }

    for (var index = 0; index < runs; index++) {
      ids.add(await startWithinDeadline());
    }
    final enqueueMicros = timer.elapsedMicroseconds;
    // Compute once before creating any waiters so a deadline exception cannot
    // abandon a partially constructed list of polling futures.
    final waitTimeout = runs == 0 ? Duration.zero : remaining();
    final results = await Future.wait([
      for (final id in ids)
        app.waitForCompletion<int>(id, timeout: waitTimeout),
    ]);
    final expectedValue = config.steps * (config.steps + 1) ~/ 2;
    for (var index = 0; index < results.length; index++) {
      final result = results[index];
      if (result == null ||
          result.timedOut ||
          !result.isCompleted ||
          result.value != expectedValue) {
        throw StateError(
          '$phase run ${ids[index]} did not complete correctly: '
          'status=${result?.status.name}, timedOut=${result?.timedOut}, '
          'value=${result?.value}, expected=$expectedValue, '
          'error=${result?.state.lastError}',
        );
      }
    }
    final checkpoints = checkpointsExecuted() - initialCheckpoints;
    if (results.length != runs ||
        ids.toSet().length != runs ||
        checkpoints != runs * config.steps) {
      throw StateError('$phase run/checkpoint count mismatch.');
    }
    timer.stop();
    succeeded = true;
    return {
      'startedAtUtc': startedAt.toIso8601String(),
      'finishedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'startedTimelineMicros': startedTimelineMicros,
      'finishedTimelineMicros': Timeline.now,
      'completedRuns': results.length,
      'executedCheckpoints': checkpoints,
      'expectedResultPerRun': expectedValue,
      'enqueueMs': enqueueMicros / 1000,
      'endToEndMs': timer.elapsedMicroseconds / 1000,
      'runsPerSecond': timer.elapsedMicroseconds == 0
          ? 0.0
          : runs * 1000000 / timer.elapsedMicroseconds,
    };
  } finally {
    timer.stop();
    marker.finish(arguments: {'succeeded': succeeded});
  }
}
