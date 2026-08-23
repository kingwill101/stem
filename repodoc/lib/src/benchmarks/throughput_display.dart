import 'dart:io';

import 'package:artisanal/artisanal.dart';

void displayThroughputResults(
  List<Map<String, Object?>> results, {
  double? baseline,
  String? artifactPath,
}) {
  final console = Console(interactive: false);
  console.title('Stem throughput benchmark');
  console.table(
    headers: const ['Concurrency', 'Tasks', 'Warmup'],
    rows: [
      for (final result in results)
        [result['concurrency'], result['tasks'], result['warmup'] ?? 'n/a'],
    ],
  );
  console.section('Performance');
  console.table(
    headers: const [
      'Concurrency',
      'Enqueue/s',
      'End-to-end/s',
      'Enqueue ms',
      'Drain ms',
    ],
    rows: [
      for (final result in results)
        [
          result['concurrency'],
          _fixed(result['enqueue_tasks_per_second']),
          _fixed(result['end_to_end_tasks_per_second']),
          _fixed(result['enqueue_ms']),
          _fixed(result['drain_ms']),
        ],
    ],
  );

  if (baseline != null) {
    final failures = results
        .where((result) {
          final measured = _number(result['end_to_end_tasks_per_second']) ?? 0;
          return measured < baseline;
        })
        .toList(growable: false);
    if (failures.isEmpty) {
      console.success(
        'Baseline passed for ${results.length} bucket(s): '
        'minimum ${_fixed(baseline)} tasks/s',
      );
    } else {
      console.error(
        'Baseline failed for ${failures.length} bucket(s): '
        'minimum ${_fixed(baseline)} tasks/s',
      );
    }
  }
  if (artifactPath != null && artifactPath.isNotEmpty) {
    console.info('JSON artifact: ${File(artifactPath).absolute.path}');
  }
}

num? _number(Object? value) => value is num ? value : null;

String _fixed(Object? value) {
  final number = _number(value);
  if (number == null) return 'n/a';
  if (number.abs() >= 1000000) return number.toStringAsFixed(0);
  if (number.abs() >= 1000) return number.toStringAsFixed(1);
  if (number.abs() >= 1) return number.toStringAsFixed(2);
  return number.toStringAsFixed(3);
}
