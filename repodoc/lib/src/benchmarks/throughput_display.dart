import 'dart:io';

import 'package:artisanal/artisanal.dart';

import 'formatting.dart';

void displayThroughputResults(
  List<Map<String, Object?>> results, {
  double? baseline,
  String? artifactPath,
}) {
  final console = Console(interactive: false);
  console.title('Stem throughput benchmark');
  console.table(
    headers: const ['Store', 'Concurrency', 'Tasks', 'Warmup'],
    rows: [
      for (final result in results)
        [
          result['store'] ?? 'n/a',
          result['concurrency'],
          result['tasks'],
          result['warmup'] ?? 'n/a',
        ],
    ],
  );
  console.section('Performance');
  console.table(
    headers: const [
      'Store',
      'Concurrency',
      'Enqueue/s',
      'Handler/s',
      'End-to-end/s',
      'Enqueue ms',
      'Store drain ms',
    ],
    rows: [
      for (final result in results)
        [
          result['store'] ?? 'n/a',
          result['concurrency'],
          benchmarkFixed(result['enqueue_tasks_per_second']),
          benchmarkFixed(result['handler_end_to_end_tasks_per_second']),
          benchmarkFixed(result['end_to_end_tasks_per_second']),
          benchmarkFixed(result['enqueue_ms']),
          benchmarkFixed(result['store_drain_ms']),
        ],
    ],
  );

  if (baseline != null) {
    final failures = results
        .where((result) {
          final measured =
              benchmarkNumber(result['end_to_end_tasks_per_second']) ?? 0;
          return measured < baseline;
        })
        .toList(growable: false);
    if (failures.isEmpty) {
      console.success(
        'Baseline passed for ${results.length} bucket(s): '
        'minimum ${benchmarkFixed(baseline)} tasks/s',
      );
    } else {
      console.error(
        'Baseline failed for ${failures.length} bucket(s): '
        'minimum ${benchmarkFixed(baseline)} tasks/s',
      );
    }
  }

  final timingResults = results
      .where((result) => result['postgres_timings'] is List)
      .toList(growable: false);
  if (timingResults.isNotEmpty) {
    console.section('PostgreSQL operation timings');
    console.table(
      headers: const [
        'Concurrency',
        'Operation',
        'Count',
        'Avg ms',
        'P95 ms',
        'Max ms',
        'Avg exec ms',
        'Avg queue ms',
      ],
      rows: [
        for (final result in timingResults)
          for (final timing in (result['postgres_timings']! as List))
            if (timing is Map)
              [
                result['concurrency'],
                timing['operation'] ?? 'n/a',
                timing['count'] ?? 'n/a',
                benchmarkFixed(timing['avg_ms']),
                benchmarkFixed(timing['p95_ms']),
                benchmarkFixed(timing['max_ms']),
                benchmarkFixed(timing['avg_execution_ms']),
                benchmarkFixed(timing['avg_queue_wait_ms']),
              ],
      ],
    );

    final queryRows = [
      for (final result in timingResults)
        for (final query in _queryValues(result['postgres_queries']))
          if (query is Map) {'concurrency': result['concurrency'], ...query},
    ];
    if (queryRows.isNotEmpty) {
      final title = queryRows.length > 20
          ? 'PostgreSQL query timings (slowest first; '
                'showing 20 of ${queryRows.length})'
          : 'PostgreSQL query timings (slowest first)';
      console.section(title);
      console.table(
        headers: const [
          'Concurrency',
          'Component',
          'Count',
          'Avg ms',
          'P95 ms',
          'Max ms',
          'SQL',
        ],
        rows: [
          for (final query in queryRows.take(20))
            [
              query['concurrency'],
              query['component'] ?? 'n/a',
              query['count'] ?? 'n/a',
              benchmarkFixed(query['avg_ms']),
              benchmarkFixed(query['p95_ms']),
              benchmarkFixed(query['max_ms']),
              _sqlPreview(query['sql']),
            ],
        ],
      );
    }
  }
  if (artifactPath != null && artifactPath.isNotEmpty) {
    console.info('JSON artifact: ${File(artifactPath).absolute.path}');
  }
}

Iterable<Object?> _queryValues(Object? value) =>
    value is List ? value : const <Object?>[];

String _sqlPreview(Object? value) {
  if (value is! String || value.isEmpty) return 'n/a';
  final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= 120) return normalized;
  return '${normalized.substring(0, 117)}...';
}
