import 'dart:io';

import 'package:artisanal/artisanal.dart';

import '../repodoc/lib/src/benchmarks/formatting.dart';

void displayThroughputResult(
  Map<String, Object?> result, {
  double? baseline,
  String? artifactPath,
}) {
  final console = Console(interactive: false);
  console.title('Stem throughput benchmark');
  console.table(
    headers: const ['Scenario', 'Value'],
    rows: [
      ['Tasks', result['tasks'] ?? 'n/a'],
      ['Concurrency', result['concurrency'] ?? 'n/a'],
    ],
  );
  console.section('Performance');
  console.table(
    headers: const ['Metric', 'Value'],
    rows: [
      ['Enqueue time', '${benchmarkFixed(result['enqueue_ms'])} ms'],
      ['End-to-end time', '${benchmarkFixed(result['end_to_end_ms'])} ms'],
      [
        'Enqueue throughput',
        '${benchmarkFixed(result['enqueue_tasks_per_second'])} tasks/s',
      ],
      [
        'End-to-end throughput',
        '${benchmarkFixed(result['end_to_end_tasks_per_second'])} tasks/s',
      ],
    ],
  );

  if (baseline != null) {
    final measured =
        benchmarkNumber(result['end_to_end_tasks_per_second']) ?? 0;
    if (measured >= baseline) {
      console.success(
        'Baseline passed: ${benchmarkFixed(measured)} >= '
        '${benchmarkFixed(baseline)} tasks/s',
      );
    } else {
      console.error(
        'Baseline failed: ${benchmarkFixed(measured)} < '
        '${benchmarkFixed(baseline)} tasks/s',
      );
    }
  }
  _printArtifact(console, artifactPath);
}

void displayAotProfileResult(
  Map<String, Object?> result, {
  required String artifactPath,
}) {
  final console = Console(interactive: false);
  final scenario = _map(result['scenario']);
  final summary = _map(result['summary']);

  console.title('Stem AOT job profile');
  console.table(
    headers: const ['Scenario', 'Value'],
    rows: [
      ['Tasks', scenario['tasks'] ?? 'n/a'],
      ['Warmup tasks', scenario['warmup'] ?? 'n/a'],
      ['Concurrency', scenario['concurrency'] ?? 'n/a'],
      ['Execution mode', scenario['mode'] ?? 'n/a'],
      ['Workload', scenario['workload'] ?? 'n/a'],
      ['Work units', scenario['workUnits'] ?? 'n/a'],
      ['Trials', result['repetitions'] ?? 'n/a'],
    ],
  );
  console.section('Trial summaries');
  console.table(
    headers: const ['Metric', 'Median', 'P95 trial', 'Unit'],
    rows: [
      _summaryRow(
        summary,
        'enqueueTasksPerSecond',
        'Enqueue throughput',
        'tasks/s',
      ),
      _summaryRow(
        summary,
        'endToEndTasksPerSecond',
        'End-to-end throughput',
        'tasks/s',
      ),
      _summaryRow(summary, 'enqueueMs', 'Enqueue time', 'ms'),
      _summaryRow(summary, 'endToEndMs', 'End-to-end time', 'ms'),
      _summaryRow(summary, 'queueLatencyP95Ms', 'Queue latency', 'ms'),
      _summaryRow(summary, 'executionLatencyP95Ms', 'Execution latency', 'ms'),
      _summaryRow(
        summary,
        'taskEndToEndLatencyP95Ms',
        'Task end-to-end latency',
        'ms',
      ),
      _summaryRow(summary, 'rssAfterBytes', 'RSS after', 'bytes'),
    ],
  );
  final gitSha = result['gitSha'];
  if (gitSha != null) console.info('Git SHA: $gitSha');
  _printArtifact(console, artifactPath);
}

List<Object?> _summaryRow(
  Map<String, Object?> summary,
  String key,
  String label,
  String unit,
) {
  final metric = _map(summary[key]);
  return [
    label,
    benchmarkFixed(metric['median']),
    benchmarkFixed(metric['p95']),
    unit,
  ];
}

void _printArtifact(Console console, String? artifactPath) {
  if (artifactPath == null || artifactPath.isEmpty) return;
  console.info('JSON artifact: ${File(artifactPath).absolute.path}');
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map) return const {};
  return {for (final entry in value.entries) entry.key.toString(): entry.value};
}
