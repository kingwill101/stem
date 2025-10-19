import 'dart:io';

import 'dart:convert';

import 'package:args/args.dart';

import '../core/contracts.dart';
import '../observability/metrics.dart';
import '../observability/snapshots.dart';
import '../scheduler/schedule_calculator.dart';
import 'file_schedule_repository.dart';

Future<int> runStemCli(
  List<String> arguments, {
  StringSink? out,
  StringSink? err,
  String? scheduleFilePath,
}) async {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;

  final parser = ArgParser();
  final scheduleParser = ArgParser();
  final observeParser = ArgParser();

  scheduleParser.addCommand('list');

  final addCommand = scheduleParser.addCommand('add')
    ..addOption('id', help: 'Unique identifier', valueHelp: 'id')
    ..addOption('task', help: 'Task name', valueHelp: 'task-name')
    ..addOption('queue', help: 'Queue name', defaultsTo: 'default')
    ..addOption(
      'spec',
      help: 'Schedule spec (every:5m or cron)',
      valueHelp: 'spec',
    )
    ..addMultiOption(
      'arg',
      help: 'Task argument key=value',
      valueHelp: 'key=value',
    )
    ..addOption('jitter', help: 'Jitter duration (e.g. 500ms, 5s)');

  final removeCommand = scheduleParser.addCommand('remove')
    ..addOption('id', help: 'Schedule identifier', valueHelp: 'id');

  final dryRunCommand = scheduleParser.addCommand('dry-run')
    ..addOption('spec', help: 'Schedule spec', valueHelp: 'spec')
    ..addOption('count', help: 'Number of occurrences', defaultsTo: '5')
    ..addOption('from', help: 'Start timestamp ISO8601', valueHelp: 'time');

  parser.addCommand('schedule', scheduleParser);

  observeParser.addCommand('metrics');
  observeParser.addCommand('queues')
    ..addOption('file', abbr: 'f', help: 'Path to queue snapshot JSON');
  observeParser.addCommand('workers')
    ..addOption('file', abbr: 'f', help: 'Path to worker snapshot JSON');
  observeParser.addCommand('dlq')
    ..addOption('file', abbr: 'f', help: 'Path to DLQ snapshot JSON');
  observeParser.addCommand('schedules')
    ..addOption('file', abbr: 'f', help: 'Path to schedules file');

  parser.addCommand('observe', observeParser);

  ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (e) {
    stderrSink.writeln('Error: ${e.message}');
    stderrSink.writeln(_usage(parser));
    return 64;
  }

  final command = results.command;
  if (command == null) {
    stdoutSink.writeln(_usage(parser));
    return 64;
  }

  if (command.name == 'schedule') {
    final sub = command.command;
    if (sub == null) {
      stdoutSink.writeln(_scheduleUsage(scheduleParser));
      return 64;
    }

    final repo = FileScheduleRepository(path: scheduleFilePath);
    switch (sub.name) {
      case 'list':
        return _listSchedules(repo, stdoutSink);
      case 'add':
        return _addSchedule(repo, sub, stdoutSink, stderrSink);
      case 'remove':
        return _removeSchedule(repo, sub, stdoutSink, stderrSink);
      case 'dry-run':
        return _dryRun(sub, stdoutSink, stderrSink);
      default:
        stderrSink.writeln('Unknown schedule subcommand: ${sub.name}');
        stdoutSink.writeln(_scheduleUsage(scheduleParser));
        return 64;
    }
  }

  if (command.name == 'observe') {
    final sub = command.command;
    if (sub == null) {
      stdoutSink.writeln(_observeUsage(observeParser));
      return 64;
    }

    switch (sub.name) {
      case 'metrics':
        return _observeMetrics(stdoutSink);
      case 'queues':
        return _observeQueues(sub, stdoutSink, stderrSink);
      case 'workers':
        return _observeWorkers(sub, stdoutSink, stderrSink);
      case 'dlq':
        return _observeDlq(sub, stdoutSink, stderrSink);
      case 'schedules':
        return _observeSchedules(sub, stdoutSink, stderrSink, scheduleFilePath);
      default:
        stderrSink.writeln('Unknown observe subcommand: ${sub.name}');
        stdoutSink.writeln(_observeUsage(observeParser));
        return 64;
    }
  }

  stderrSink.writeln('Unknown command: ${command.name}');
  stderrSink.writeln(_usage(parser));
  return 64;
}

String _usage(ArgParser parser) => 'Usage: stem <command>\n${parser.usage}';
String _scheduleUsage(ArgParser parser) =>
    'Usage: stem schedule <subcommand>\n${parser.usage}';
String _observeUsage(ArgParser parser) =>
    'Usage: stem observe <subcommand>\n${parser.usage}';

Future<int> _listSchedules(FileScheduleRepository repo, StringSink out) async {
  final entries = await repo.load();
  if (entries.isEmpty) {
    out.writeln('No schedules found.');
    return 0;
  }
  out.writeln(
    'ID        | Task           | Queue    | Spec             | Enabled',
  );
  out.writeln(
    '----------+----------------+----------+------------------+---------',
  );
  for (final entry in entries) {
    out.writeln(
      '${entry.id.padRight(10)}| '
      '${entry.taskName.padRight(15)}| '
      '${entry.queue.padRight(9)}| '
      '${entry.spec.padRight(17)}| '
      '${entry.enabled ? 'yes' : 'no'}',
    );
  }
  return 0;
}

Future<int> _addSchedule(
  FileScheduleRepository repo,
  ArgResults args,
  StringSink out,
  StringSink err,
) async {
  final id = args['id'] as String?;
  final task = args['task'] as String?;
  final queue = args['queue'] as String? ?? 'default';
  final spec = args['spec'] as String?;
  if (id == null || task == null || spec == null) {
    err.writeln('Missing required options: --id, --task, --spec');
    return 64;
  }
  final jitter = _parseOptionalDuration(args['jitter'] as String?);
  if (args['jitter'] != null && jitter == null) {
    err.writeln('Invalid jitter value: ${args['jitter']}');
    return 64;
  }
  final argList = (args['arg'] as List<String>? ?? const []);
  final argMap = <String, Object?>{};
  for (final pair in argList) {
    final parts = pair.split('=');
    if (parts.length != 2) {
      err.writeln('Invalid argument format: $pair. Use key=value');
      return 64;
    }
    argMap[parts[0]] = parts[1];
  }

  final entries = await repo.load();
  if (entries.any((e) => e.id == id)) {
    err.writeln('Schedule "$id" already exists.');
    return 64;
  }

  final entry = ScheduleEntry(
    id: id,
    taskName: task,
    queue: queue,
    spec: spec,
    args: argMap,
    jitter: jitter,
  );

  entries.add(entry);
  await repo.save(entries);
  out.writeln('Added schedule "$id".');
  return 0;
}

Future<int> _removeSchedule(
  FileScheduleRepository repo,
  ArgResults args,
  StringSink out,
  StringSink err,
) async {
  final id = args['id'] as String?;
  if (id == null) {
    err.writeln('Missing required option: --id');
    return 64;
  }
  final entries = await repo.load();
  final removed = entries.where((e) => e.id != id).toList();
  if (removed.length == entries.length) {
    err.writeln('Schedule "$id" not found.');
    return 64;
  }
  await repo.save(removed);
  out.writeln('Removed schedule "$id".');
  return 0;
}

Future<int> _dryRun(ArgResults args, StringSink out, StringSink err) async {
  final spec = args['spec'] as String?;
  if (spec == null) {
    err.writeln('Missing required option: --spec');
    return 64;
  }
  final count = int.tryParse(args['count'] as String? ?? '5') ?? 5;
  DateTime start;
  if (args['from'] != null) {
    try {
      start = DateTime.parse(args['from'] as String);
    } catch (_) {
      err.writeln('Invalid --from timestamp. Use ISO-8601 format.');
      return 64;
    }
  } else {
    start = DateTime.now();
  }
  final calculator = ScheduleCalculator();
  final entry = ScheduleEntry(
    id: '_dry_',
    taskName: '_dry_',
    queue: 'default',
    spec: spec,
  );
  var current = entry.copyWith(lastRunAt: start);
  for (var i = 0; i < count; i++) {
    final next = calculator.nextRun(current, start, includeJitter: false);
    out.writeln(next.toIso8601String());
    current = current.copyWith(lastRunAt: next);
  }
  return 0;
}

Duration? _parseOptionalDuration(String? value) {
  if (value == null) return null;
  final match = RegExp(r'^(\d+)(ms|s|m|h)$').firstMatch(value.trim());
  if (match == null) return null;
  final number = int.parse(match.group(1)!);
  switch (match.group(2)) {
    case 'ms':
      return Duration(milliseconds: number);
    case 's':
      return Duration(seconds: number);
    case 'm':
      return Duration(minutes: number);
    case 'h':
      return Duration(hours: number);
  }
  return null;
}

Future<int> _observeMetrics(StringSink out) async {
  final snapshot = StemMetrics.instance.snapshot();
  out.writeln(jsonEncode(snapshot));
  return 0;
}

Future<int> _observeQueues(
  ArgResults args,
  StringSink out,
  StringSink err,
) async {
  final path = args['file'] as String?;
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

Future<int> _observeWorkers(
  ArgResults args,
  StringSink out,
  StringSink err,
) async {
  final path = args['file'] as String?;
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

Future<int> _observeDlq(ArgResults args, StringSink out, StringSink err) async {
  final path = args['file'] as String?;
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

Future<int> _observeSchedules(
  ArgResults args,
  StringSink out,
  StringSink err,
  String? defaultFile,
) async {
  final repoPath = args['file'] as String? ?? defaultFile;
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
