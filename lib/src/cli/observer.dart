import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:stem/src/cli/dependencies.dart';
import 'package:stem/src/cli/file_schedule_repository.dart';
import 'package:stem/src/cli/utilities.dart';
import 'package:stem/src/observability/snapshots.dart';
import 'package:stem/src/scheduler/schedule_calculator.dart';
import 'package:stem/stem.dart';

class ObserveCommand extends Command<int> {
  ObserveCommand(this.dependencies) {
    addSubcommand(ObserveMetricsCommand(dependencies));
    addSubcommand(ObserveQueuesCommand(dependencies));
    addSubcommand(ObserveWorkersCommand(dependencies));
    addSubcommand(ObserveDlqCommand(dependencies));
    addSubcommand(ObserveSchedulesCommand(dependencies));
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'observe';

  @override
  final String description = 'Inspect metrics, queues, workers, and schedules.';

  @override
  Future<int> run() async {
    throw UsageException('Specify an observe subcommand.', usage);
  }
}

class ObserveMetricsCommand extends Command<int> {
  ObserveMetricsCommand(this.dependencies);

  final StemCommandDependencies dependencies;

  @override
  final String name = 'metrics';

  @override
  final String description = 'Print metrics snapshot as JSON.';

  @override
  Future<int> run() async {
    final snapshot = StemMetrics.instance.snapshot();
    dependencies.out.writeln(jsonEncode(snapshot));
    return 0;
  }
}

class ObserveQueuesCommand extends Command<int> {
  ObserveQueuesCommand(this.dependencies) {
    argParser.addOption('file', abbr: 'f', help: 'Path to queue snapshot JSON');
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'queues';

  @override
  final String description = 'Display queue snapshot information.';

  @override
  Future<int> run() async {
    final out = dependencies.out;
    final err = dependencies.err;
    final path = argResults!['file'] as String?;
    if (path == null) {
      err.writeln('Missing --file pointing to queue snapshot JSON.');
      return 64;
    }
    final report = ObservabilityReport.fromFile(path);
    if (report.queues.isEmpty) {
      out.writeln('No queue data.');
      return 0;
    }
    out.writeln('Queue     | Pending | Inflight');
    out.writeln('----------+---------+---------');
    for (final queue in report.queues) {
      out.writeln(
        '${queue.queue.padRight(10)}| '
        '${queue.pending.toString().padLeft(7)} | '
        '${queue.inflight.toString().padLeft(7)}',
      );
    }
    return 0;
  }
}

class ObserveWorkersCommand extends Command<int> {
  ObserveWorkersCommand(this.dependencies) {
    argParser.addOption(
      'file',
      abbr: 'f',
      help: 'Path to worker snapshot JSON',
    );
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'workers';

  @override
  final String description = 'Display worker snapshot information.';

  @override
  Future<int> run() async {
    final out = dependencies.out;
    final err = dependencies.err;
    final path = argResults!['file'] as String?;
    if (path == null) {
      err.writeln('Missing --file pointing to worker snapshot JSON.');
      return 64;
    }
    final report = ObservabilityReport.fromFile(path);
    if (report.workers.isEmpty) {
      out.writeln('No worker data.');
      return 0;
    }
    out.writeln('Worker        | Active | Last Heartbeat');
    out.writeln('--------------+--------+----------------');
    for (final worker in report.workers) {
      out.writeln(
        '${worker.id.padRight(14)}| '
        '${worker.active.toString().padLeft(6)} | '
        '${worker.lastHeartbeat.toIso8601String()}',
      );
    }
    return 0;
  }
}

class ObserveDlqCommand extends Command<int> {
  ObserveDlqCommand(this.dependencies) {
    argParser.addOption('file', abbr: 'f', help: 'Path to DLQ snapshot JSON');
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'dlq';

  @override
  final String description = 'Display dead-letter queue snapshot.';

  @override
  Future<int> run() async {
    final out = dependencies.out;
    final err = dependencies.err;
    final path = argResults!['file'] as String?;
    if (path == null) {
      err.writeln('Missing --file pointing to DLQ snapshot JSON.');
      return 64;
    }
    final report = ObservabilityReport.fromFile(path);
    if (report.dlq.isEmpty) {
      out.writeln('Dead letter queue is empty.');
      return 0;
    }
    out.writeln('Queue     | Task ID                        | Reason');
    out.writeln('----------+--------------------------------+----------------');
    for (final entry in report.dlq) {
      out.writeln(
        '${entry.queue.padRight(10)}| '
        '${entry.taskId.padRight(32)}| '
        '${entry.reason}',
      );
    }
    return 0;
  }
}

class ObserveSchedulesCommand extends Command<int> {
  ObserveSchedulesCommand(this.dependencies) {
    argParser.addOption(
      'file',
      abbr: 'f',
      help: 'Path to schedules snapshot file',
    );
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'schedules';

  @override
  final String description = 'Display schedule snapshot information.';

  @override
  Future<int> run() async {
    final out = dependencies.out;
    final scheduleCtx = await dependencies.createScheduleContext();
    try {
      final repoPath =
          argResults!['file'] as String? ?? dependencies.scheduleFilePath;
      FileScheduleRepository? fileRepo;
      if (repoPath != null) {
        fileRepo = FileScheduleRepository(path: repoPath);
      } else {
        fileRepo = scheduleCtx.repo;
      }
      final entries = scheduleCtx.store != null
          ? await scheduleCtx.store!.list()
          : await (fileRepo ?? FileScheduleRepository()).load();
      if (entries.isEmpty) {
        out.writeln('No schedules found.');
        return 0;
      }
      final calculator = ScheduleCalculator();
      final now = DateTime.now();
      var dueCount = 0;
      var overdueCount = 0;
      Duration? maxDrift;
      for (final entry in entries) {
        final next =
            entry.nextRunAt ??
            calculator.nextRun(
              entry.copyWith(lastRunAt: entry.lastRunAt ?? now),
              entry.lastRunAt ?? now,
              includeJitter: false,
            );
        if (!next.isAfter(now)) {
          dueCount += 1;
          overdueCount += 1;
        }
        final drift = entry.drift;
        if (drift != null) {
          final magnitude = drift.abs();
          if (maxDrift == null || magnitude > maxDrift) {
            maxDrift = magnitude;
          }
        }
      }

      final metricsSnapshot = StemMetrics.instance.snapshot();
      double? dueGauge = _gaugeValue(
        metricsSnapshot,
        'stem.scheduler.due.entries',
      );
      double? overdueGauge = _gaugeValue(
        metricsSnapshot,
        'stem.scheduler.overdue.entries',
      );
      out.writeln(
        'Summary: due=$dueCount overdue=$overdueCount'
        '${dueGauge != null ? ' (gauge=${dueGauge.toStringAsFixed(0)})' : ''}'
        '${overdueGauge != null ? ', gaugeOverdue=${overdueGauge.toStringAsFixed(0)}' : ''}'
        '${maxDrift != null ? ', maxDrift=${formatDuration(maxDrift)}' : ''}',
      );

      out.writeln(
        'ID        | Task           | Queue     | Next Run                | Last Run                | Total | Drift   | Last Error',
      );
      out.writeln(
        '----------+----------------+-----------+------------------------+------------------------+-------+---------+-----------',
      );
      for (final entry in entries) {
        final reference = entry.lastRunAt ?? now;
        final next =
            entry.nextRunAt ??
            calculator.nextRun(
              entry.copyWith(lastRunAt: reference),
              reference,
              includeJitter: false,
            );
        final drift = entry.drift != null ? formatDuration(entry.drift) : '-';
        final lastError = (entry.lastError?.isEmpty ?? true)
            ? '-'
            : entry.lastError!;
        out.writeln(
          '${entry.id.padRight(10)}| '
          '${entry.taskName.padRight(16)}| '
          '${entry.queue.padRight(10)}| '
          '${next.toIso8601String().padRight(24)}| '
          '${formatDateTime(entry.lastRunAt).padRight(24)}| '
          '${entry.totalRunCount.toString().padLeft(5)} | '
          '${drift.toString().padRight(7)} | '
          '$lastError',
        );
      }
      return 0;
    } finally {
      await scheduleCtx.dispose();
    }
  }
}

double? _gaugeValue(Map<String, Object> snapshot, String name) {
  final gauges = snapshot['gauges'];
  if (gauges is! List) return null;
  for (final entry in gauges) {
    if (entry is Map && entry['name'] == name) {
      final value = entry['value'];
      if (value is num) return value.toDouble();
    }
  }
  return null;
}
