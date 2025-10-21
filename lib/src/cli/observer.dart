import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:stem/src/cli/dependencies.dart';
import 'package:stem/src/cli/file_schedule_repository.dart';
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
    argParser.addOption(
      'file',
      abbr: 'f',
      help: 'Path to queue snapshot JSON',
    );
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
    argParser.addOption(
      'file',
      abbr: 'f',
      help: 'Path to DLQ snapshot JSON',
    );
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
    final repoPath =
        argResults!['file'] as String? ?? dependencies.scheduleFilePath;
    final repo = FileScheduleRepository(path: repoPath);
    final entries = await repo.load();
    if (entries.isEmpty) {
      out.writeln('No schedules found.');
      return 0;
    }
    final calculator = ScheduleCalculator();
    out.writeln('ID        | Task           | Next Run           | Queue');
    out.writeln('----------+----------------+--------------------+----------');
    final now = DateTime.now();
    for (final entry in entries) {
      final next = calculator.nextRun(entry, entry.lastRunAt ?? now);
      out.writeln(
        '${entry.id.padRight(10)}| '
        '${entry.taskName.padRight(16)}| '
        '${next.toIso8601String()} | '
        '${entry.queue}',
      );
    }
    return 0;
  }
}
