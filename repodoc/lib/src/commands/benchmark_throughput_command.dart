import 'dart:convert';
import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:path/path.dart' as p;

import '../benchmarks/throughput.dart';
import '../benchmarks/throughput_mode.dart';
import '../benchmarks/throughput_statistics.dart';
import '../benchmarks/throughput_store.dart';
import '../benchmarks/throughput_display.dart';
import '../infrastructure/workspace.dart';

final class BenchmarkThroughputCommand extends Command<int> {
  BenchmarkThroughputCommand() {
    argParser
      ..addOption('tasks', defaultsTo: '5000')
      ..addOption('warmup', defaultsTo: '250')
      ..addOption('concurrency', defaultsTo: '8')
      ..addOption(
        'mode',
        defaultsTo: 'steady-state',
        help: 'Workload mode: steady-state, enqueue-only, or prefilled-drain.',
      )
      ..addOption(
        'duration',
        help:
            'Measurement window for duration-based runs, for example 10s or '
            '1m. Omit to use --tasks.',
      )
      ..addOption(
        'samples',
        defaultsTo: '1',
        help: 'Number of repeated trials for each store and bucket.',
      )
      ..addOption(
        'store',
        help: 'Store to benchmark: memory, sqlite, postgres, or redis.',
        valueHelp: 'memory|sqlite|postgres|redis',
      )
      ..addOption(
        'stores',
        help: 'Comma-separated store sweep, for example memory,sqlite,redis.',
        valueHelp: 'memory,sqlite,postgres,redis',
      )
      ..addOption(
        'buckets',
        help: 'Comma-separated concurrency buckets, for example 4,8,16.',
        valueHelp: '4,8,16',
      )
      ..addOption(
        'postgres-url',
        help: 'PostgreSQL URL; defaults to STEM_BENCHMARK_POSTGRES_URL.',
      )
      ..addOption(
        'redis-url',
        help: 'Redis URL; defaults to STEM_BENCHMARK_REDIS_URL.',
      )
      ..addOption(
        'sqlite-path',
        help:
            'SQLite database path; otherwise a temporary .tmp database is used.',
      )
      ..addFlag('verbose', help: 'Log benchmark lifecycle stages to stderr.')
      ..addFlag(
        'timings',
        help: 'Collect PostgreSQL broker and backend operation timings.',
        negatable: false,
      )
      ..addOption('output')
      ..addFlag(
        'check-baseline',
        help: 'Fail if end-to-end throughput is below the checked-in baseline.',
        negatable: false,
      )
      ..addFlag(
        'json',
        help: 'Print the raw JSON result instead of the terminal summary.',
        negatable: false,
      );
  }

  @override
  String get name => 'benchmark:throughput';

  @override
  String get description =>
      'Benchmark Stem throughput against one or more backing stores.';

  @override
  Future<int> run() async {
    final catalog = WorkspaceCatalog.load();
    final tasks = _positiveInt('tasks');
    final warmup = _nonNegativeInt('warmup');
    final mode = ThroughputMode.parse(_option('mode'));
    final duration = _optionalDuration('duration');
    final samples = _positiveInt('samples');
    final jsonOutput = argResults?['json'] == true;
    final verbose = argResults?['verbose'] == true;
    final timings = argResults?['timings'] == true;
    final stores = _stores();
    final checkBaseline = argResults?['check-baseline'] == true;
    final runtime = _runtime();
    if (checkBaseline && mode != ThroughputMode.steadyState) {
      throw ArgumentError(
        '--check-baseline currently applies only to steady-state '
        'end-to-end throughput.',
      );
    }
    if (checkBaseline &&
        stores.any((store) => store != ThroughputStore.memory)) {
      throw ArgumentError(
        '--check-baseline currently has a checked-in baseline only for '
        'the memory store. Run external-store benchmarks without it until '
        'store-specific baselines are established.',
      );
    }
    final postgresUrl = _connectionOption(
      'postgres-url',
      'STEM_BENCHMARK_POSTGRES_URL',
      'postgresql://stem:stem@127.0.0.1:5432/stem_benchmark',
    );
    final redisUrl = _connectionOption(
      'redis-url',
      'STEM_BENCHMARK_REDIS_URL',
      'redis://127.0.0.1:6379/15',
    );
    final sqlitePath = argResults?['sqlite-path'] as String?;
    final output = argResults?['output'] as String?;
    final results = <Map<String, Object?>>[];
    Map<String, Object?> buildReport({required String status, Object? error}) =>
        {
          'schemaVersion': 2,
          'kind': 'stem.throughput.benchmark',
          'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
          'status': status,
          'runtime': runtime,
          'mode': mode.name,
          'duration_ms': duration?.inMicroseconds == null
              ? null
              : duration!.inMicroseconds / 1000,
          'samples': samples,
          'stores': stores.map((store) => store.name).toList(growable: false),
          'buckets': results,
          if (error != null) 'error': error.toString(),
        };
    Future<void> writeReport(Map<String, Object?> report) async {
      if (output == null || output.isEmpty) return;
      final file = File(output);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
    }

    try {
      for (final store in stores) {
        for (final concurrency in _buckets()) {
          if (!jsonOutput) {
            stdout.writeln(
              'Running ${store.name} concurrency bucket $concurrency...',
            );
          }
          final trials = <Map<String, Object?>>[];
          try {
            for (var sample = 1; sample <= samples; sample++) {
              if (samples > 1 && !jsonOutput) {
                stdout.writeln(
                  'Running ${store.name} concurrency bucket $concurrency '
                  'sample $sample/$samples...',
                );
              }
              final result = await ThroughputBenchmark(
                tasks: tasks,
                warmupTasks: warmup,
                concurrency: concurrency,
                store: store,
                mode: mode,
                measurementDuration: duration,
                postgresUrl: postgresUrl,
                redisUrl: redisUrl,
                sqlitePath: sqlitePath,
                collectPostgresTimings: timings,
                onStage: verbose ? stderr.writeln : null,
              ).run();
              trials.add(result);
            }
          } finally {
            if (trials.isNotEmpty) {
              results.add(
                _aggregateTrials(
                  trials,
                  runtime: runtime,
                  warmup: warmup,
                  samples: trials.length,
                ),
              );
            }
          }
        }
      }
    } on Object catch (error, stackTrace) {
      try {
        await writeReport(buildReport(status: 'partial', error: error));
      } on Object catch (writeError) {
        stderr.writeln('Unable to write partial benchmark report: $writeError');
      }
      Error.throwWithStackTrace(error, stackTrace);
    }

    final report = buildReport(status: 'complete');
    await writeReport(report);

    final baseline = checkBaseline ? _baselineMinimum(catalog.root) : null;
    if (jsonOutput) {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
    } else {
      displayThroughputResults(
        results,
        baseline: baseline,
        artifactPath: output,
      );
    }
    if (baseline != null) _checkBaseline(results, baseline);
    return 0;
  }

  int _positiveInt(String name) {
    final value = int.tryParse(_required(name));
    if (value == null || value <= 0) {
      throw ArgumentError('Expected a positive integer: --$name');
    }
    return value;
  }

  String _option(String name) {
    final value = argResults?[name];
    if (value is! String || value.trim().isEmpty) {
      throw ArgumentError('Missing benchmark option: --$name');
    }
    return value;
  }

  Duration? _optionalDuration(String name) {
    final value = argResults?[name] as String?;
    if (value == null || value.trim().isEmpty) return null;
    return parseThroughputDuration(value);
  }

  int _nonNegativeInt(String name) {
    final value = int.tryParse(_required(name));
    if (value == null || value < 0) {
      throw ArgumentError('Expected a non-negative integer: --$name');
    }
    return value;
  }

  List<int> _buckets() {
    final raw = argResults?['buckets'] as String?;
    if (raw == null || raw.trim().isEmpty) {
      return [_positiveInt('concurrency')];
    }
    final buckets = raw
        .split(',')
        .map((value) => int.tryParse(value.trim()))
        .toList(growable: false);
    if (buckets.any((value) => value == null || value <= 0)) {
      throw ArgumentError(
        'Expected comma-separated positive integers: --buckets 4,8,16',
      );
    }
    return buckets.cast<int>();
  }

  List<ThroughputStore> _stores() {
    final store = argResults?['store'] as String?;
    final stores = argResults?['stores'] as String?;
    if (store != null &&
        store.trim().isNotEmpty &&
        stores != null &&
        stores.trim().isNotEmpty) {
      throw ArgumentError('Use either --store or --stores, not both.');
    }
    final raw = (stores ?? store ?? 'memory')
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (raw.isEmpty) {
      throw ArgumentError('Expected at least one benchmark store.');
    }
    return raw.map(ThroughputStore.parse).toList(growable: false);
  }

  String _connectionOption(String option, String environment, String fallback) {
    final configured = argResults?[option] as String?;
    if (configured != null && configured.isNotEmpty) return configured;
    return Platform.environment[environment] ?? fallback;
  }

  String _runtime() {
    final runtime = Platform.environment['STEM_BENCHMARK_RUNTIME']?.trim();
    return runtime == null || runtime.isEmpty ? 'unknown' : runtime;
  }

  String _required(String name) {
    final value = argResults?[name];
    if (value is! String || value.isEmpty) {
      throw ArgumentError('Missing benchmark option: --$name');
    }
    return value;
  }

  double _baselineMinimum(Directory root) {
    final file = File(
      p.join(
        root.path,
        'repodoc',
        'benchmarks',
        'stem_throughput_baseline.json',
      ),
    );
    if (!file.existsSync()) {
      throw StateError('Missing benchmark baseline: ${file.path}');
    }
    final document = jsonDecode(file.readAsStringSync());
    final minimum = document is Map
        ? document['minimum_end_to_end_tasks_per_second']
        : null;
    if (minimum is! num) {
      throw StateError('Benchmark baseline has no numeric minimum.');
    }
    return minimum.toDouble();
  }

  void _checkBaseline(List<Map<String, Object?>> results, double minimum) {
    final failures = results.where((result) {
      final statistics = result['statistics'];
      final measured =
          statistics is Map && statistics['end_to_end_tasks_per_second'] is Map
          ? (statistics['end_to_end_tasks_per_second'] as Map)['median']
          : result['end_to_end_tasks_per_second'];
      return measured is! num || measured < minimum;
    });
    if (failures.isNotEmpty) {
      throw StateError(
        'Throughput regression: ${failures.length} bucket(s) are below '
        '$minimum tasks/s.',
      );
    }
  }
}

Map<String, Object?> _aggregateTrials(
  List<Map<String, Object?>> trials, {
  required String runtime,
  required int warmup,
  required int samples,
}) {
  final first = trials.first;
  final numericKeys = [
    'enqueue_tasks_per_second',
    'handler_end_to_end_tasks_per_second',
    'end_to_end_tasks_per_second',
    'enqueue_ms',
    'handler_end_to_end_ms',
    'end_to_end_ms',
    'drain_ms',
    'store_drain_ms',
  ];
  final statistics = <String, Object?>{};
  final aggregate = <String, Object?>{...first};
  for (final key in numericKeys) {
    final values = [
      for (final trial in trials)
        if (trial[key] is num) trial[key]! as num,
    ];
    final summary = ThroughputStatistics.summarize(values);
    statistics[key] = summary;
    final median = summary['median'];
    if (median != null) aggregate[key] = median;
  }
  return {
    ...aggregate,
    'runtime': runtime,
    'warmup': warmup,
    'samples': samples,
    'statistics': statistics,
    'trials': trials,
  };
}
