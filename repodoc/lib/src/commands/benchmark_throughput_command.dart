import 'dart:convert';
import 'dart:io';

import 'package:artisanal/args.dart';

import '../benchmarks/throughput.dart';
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
    final jsonOutput = argResults?['json'] == true;
    final verbose = argResults?['verbose'] == true;
    final timings = argResults?['timings'] == true;
    final stores = _stores();
    final checkBaseline = argResults?['check-baseline'] == true;
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
    final results = <Map<String, Object?>>[];
    for (final store in stores) {
      for (final concurrency in _buckets()) {
        if (!jsonOutput) {
          stdout.writeln(
            'Running ${store.name} concurrency bucket $concurrency...',
          );
        }
        final result = await ThroughputBenchmark(
          tasks: tasks,
          warmupTasks: warmup,
          concurrency: concurrency,
          store: store,
          postgresUrl: postgresUrl,
          redisUrl: redisUrl,
          sqlitePath: sqlitePath,
          collectPostgresTimings: timings,
          onStage: verbose ? stderr.writeln : null,
        ).run();
        results.add({...result, 'warmup': warmup});
      }
    }

    final report = <String, Object?>{
      'schemaVersion': 1,
      'kind': 'stem.throughput.benchmark',
      'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'stores': stores.map((store) => store.name).toList(growable: false),
      'buckets': results,
    };
    final output = argResults?['output'] as String?;
    if (output != null && output.isNotEmpty) {
      final file = File(output);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
    }

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

  String _required(String name) {
    final value = argResults?[name];
    if (value is! String || value.isEmpty) {
      throw ArgumentError('Missing benchmark option: --$name');
    }
    return value;
  }

  double _baselineMinimum(Directory root) {
    final file = File(
      '${root.path}/repodoc/benchmarks/stem_throughput_baseline.json',
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
      final measured = result['end_to_end_tasks_per_second'];
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
