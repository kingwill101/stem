import 'dart:convert';
import 'dart:io';

import 'package:artisanal/args.dart';

import '../benchmarks/throughput.dart';
import '../benchmarks/throughput_display.dart';
import '../infrastructure/workspace.dart';

final class BenchmarkThroughputCommand extends Command<int> {
  BenchmarkThroughputCommand() {
    argParser
      ..addOption('tasks', defaultsTo: '5000')
      ..addOption('warmup', defaultsTo: '250')
      ..addOption('concurrency', defaultsTo: '8')
      ..addOption(
        'buckets',
        help: 'Comma-separated concurrency buckets, for example 4,8,16.',
        valueHelp: '4,8,16',
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
      'Run the in-memory Stem throughput benchmark and baseline gate.';

  @override
  Future<int> run() async {
    final catalog = WorkspaceCatalog.load();
    final tasks = _positiveInt('tasks');
    final warmup = _nonNegativeInt('warmup');
    final jsonOutput = argResults?['json'] == true;
    final results = <Map<String, Object?>>[];
    for (final concurrency in _buckets()) {
      if (!jsonOutput) {
        stdout.writeln('Running concurrency bucket $concurrency...');
      }
      final result = await ThroughputBenchmark(
        tasks: tasks,
        warmupTasks: warmup,
        concurrency: concurrency,
      ).run();
      results.add({...result, 'warmup': warmup});
    }

    final report = <String, Object?>{
      'schemaVersion': 1,
      'kind': 'stem.throughput.benchmark',
      'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
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

    final baseline = argResults?['check-baseline'] == true
        ? _baselineMinimum(catalog.root)
        : null;
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
