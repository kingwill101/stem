import 'dart:convert';
import 'dart:io';

import '../benchmark/benchmark_display.dart';
import '../benchmark/profile_support.dart';

/// Compiles and repeats the deterministic job profile as an AOT executable.
///
/// This intentionally runs each sample in a fresh process. Isolate pools,
/// allocator state, and worker shutdown cannot leak from one trial into the
/// next trial, making the summary more useful than a single long-lived run.
Future<void> main(List<String> args) async {
  final repetitions = profileIntOption(args, '--repetitions', 5);
  if (repetitions <= 0) {
    throw ArgumentError.value(repetitions, '--repetitions');
  }

  final outputPath =
      profileStringOption(args, '--output') ??
      'build/stem-profile/aot-${_timestamp()}.json';
  final jsonOutput = args.contains('--json');
  final childArgs = _childArgs(args);
  final tempRoot = Directory(
    '${Directory.current.absolute.path}${Platform.pathSeparator}.tmp',
  );
  await tempRoot.create(recursive: true);
  final temp = await tempRoot.createTemp('stem-job-profile-');
  final executable = File(
    '${temp.path}${Platform.pathSeparator}stem_job_profile'
    '${Platform.isWindows ? '.exe' : ''}',
  );

  try {
    await _compile(executable);
    final samples = <Map<String, Object?>>[];
    for (var index = 0; index < repetitions; index++) {
      stderr.writeln('AOT profile trial ${index + 1}/$repetitions');
      samples.add(await _runSample(executable, childArgs));
    }

    final result = <String, Object?>{
      'schemaVersion': 1,
      'kind': 'stem.job.aot-profile',
      'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'gitSha': await _gitSha(),
      'dartVersion': Platform.version,
      'operatingSystem': Platform.operatingSystem,
      'processorCount': Platform.numberOfProcessors,
      'repetitions': repetitions,
      'scenario': _scenarioFromSample(samples.first),
      'samples': samples,
      'summary': _summaries(samples),
    };
    final output = File(outputPath);
    await output.parent.create(recursive: true);
    await output.writeAsString('${jsonEncode(result)}\n');
    if (jsonOutput) {
      stdout.writeln(jsonEncode(result));
    } else {
      displayAotProfileResult(result, artifactPath: output.absolute.path);
    }
  } finally {
    await temp.delete(recursive: true);
  }
}

Future<void> _compile(File executable) async {
  final result = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'exe',
    'benchmark/stem_job_profile.dart',
    '-o',
    executable.path,
  ]);
  if (result.exitCode != 0) {
    throw ProcessException(
      Platform.resolvedExecutable,
      ['compile', 'exe', 'benchmark/stem_job_profile.dart'],
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
}

Future<Map<String, Object?>> _runSample(
  File executable,
  List<String> args,
) async {
  final result = await Process.run(executable.path, args);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable.path,
      args,
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
  final lines = result.stdout.toString().trim().split('\n').reversed;
  for (final line in lines) {
    final candidate = line.trim();
    if (!candidate.startsWith('{')) continue;
    final decoded = jsonDecode(candidate);
    if (decoded is Map) {
      return decoded.cast<String, Object?>();
    }
  }
  throw StateError(
    'AOT profile produced no JSON sample. Output: ${result.stdout}',
  );
}

List<String> _childArgs(List<String> args) {
  const childOptions = {
    '--tasks',
    '--warmup',
    '--concurrency',
    '--mode',
    '--workload',
    '--work-units',
    '--hold-seconds',
  };
  final child = <String>[];
  for (var index = 0; index < args.length; index++) {
    final arg = args[index];
    if (arg == '--repetitions' || arg == '--output') {
      if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
        throw ArgumentError('Missing value for $arg.');
      }
      index += 1;
      continue;
    }
    if (arg == '--json') {
      continue;
    }
    if (arg.startsWith('--repetitions=') || arg.startsWith('--output=')) {
      if (arg.endsWith('=')) {
        throw ArgumentError('Missing value for ${arg.split('=').first}.');
      }
      continue;
    }
    if (arg.startsWith('--')) {
      final option = arg.split('=').first;
      if (!childOptions.contains(option)) {
        throw ArgumentError('Unknown profile option: $arg.');
      }
      if (arg.contains('=')) {
        if (arg.endsWith('=')) {
          throw ArgumentError('Missing value for $option.');
        }
        child.add(arg);
        continue;
      }
      if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
        throw ArgumentError('Missing value for $arg.');
      }
      child.add(arg);
      child.add(args[++index]);
      continue;
    }
    throw ArgumentError('Unexpected profile argument: $arg.');
  }
  return child;
}

Map<String, Object?> _scenarioFromSample(Map<String, Object?> sample) {
  return {
    'tasks': sample['tasks'],
    'warmup': sample['warmupTasks'],
    'concurrency': sample['concurrency'],
    'mode': sample['executionMode'],
    'workload': sample['workload'],
    'workUnits': sample['workUnits'],
  };
}

Map<String, Object?> _summaries(List<Map<String, Object?>> samples) {
  final paths = <String, List<double>>{};
  for (final sample in samples) {
    _addMetric(paths, 'enqueueMs', sample['enqueueMs']);
    _addMetric(paths, 'endToEndMs', sample['endToEndMs']);
    _addMetric(paths, 'enqueueTasksPerSecond', sample['enqueueTasksPerSecond']);
    _addMetric(
      paths,
      'endToEndTasksPerSecond',
      sample['endToEndTasksPerSecond'],
    );
    _addMetric(paths, 'rssBeforeBytes', sample['rssBeforeBytes']);
    _addMetric(paths, 'rssAfterBytes', sample['rssAfterBytes']);
    final queue = sample['queueLatencyMs'];
    final execution = sample['executionLatencyMs'];
    final endToEnd = sample['taskEndToEndLatencyMs'];
    if (queue is Map) _addMetric(paths, 'queueLatencyP95Ms', queue['p95']);
    if (execution is Map) {
      _addMetric(paths, 'executionLatencyP95Ms', execution['p95']);
    }
    if (endToEnd is Map) {
      _addMetric(paths, 'taskEndToEndLatencyP95Ms', endToEnd['p95']);
    }
  }
  return paths.map((key, values) => MapEntry(key, _statistics(values)));
}

void _addMetric(Map<String, List<double>> metrics, String key, Object? value) {
  if (value is num && value.isFinite) {
    metrics.putIfAbsent(key, () => []).add(value.toDouble());
  }
}

Map<String, Object?> _statistics(List<double> values) {
  final sorted = List<double>.from(values)..sort();
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

Future<String?> _gitSha() async {
  final result = await Process.run('git', ['rev-parse', 'HEAD']);
  if (result.exitCode != 0) return null;
  return result.stdout.toString().trim();
}

String _timestamp() {
  return DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
}
