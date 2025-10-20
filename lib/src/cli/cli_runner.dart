import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import '../backend/in_memory_backend.dart';
import '../backend/redis_backend.dart';
import '../broker_redis/in_memory_broker.dart';
import '../broker_redis/redis_broker.dart';
import '../core/config.dart';
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
  Future<CliContext> Function()? contextBuilder,
}) async {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;

  final parser = ArgParser();
  final scheduleParser = ArgParser();
  final observeParser = ArgParser();
  final dlqCommandParser = ArgParser();

  scheduleParser.addCommand('list');

  final addParser = scheduleParser.addCommand('add');
  addParser
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

  final removeParser = scheduleParser.addCommand('remove');
  removeParser.addOption('id', help: 'Schedule identifier', valueHelp: 'id');

  final dryRunParser = scheduleParser.addCommand('dry-run');
  dryRunParser
    ..addOption('spec', help: 'Schedule spec', valueHelp: 'spec')
    ..addOption('count', help: 'Number of occurrences', defaultsTo: '5')
    ..addOption('from', help: 'Start timestamp ISO8601', valueHelp: 'time');

  parser.addCommand('schedule', scheduleParser);

  observeParser.addCommand('metrics');
  final queuesParser = observeParser.addCommand('queues');
  queuesParser.addOption(
    'file',
    abbr: 'f',
    help: 'Path to queue snapshot JSON',
  );
  final workersParser = observeParser.addCommand('workers');
  workersParser.addOption(
    'file',
    abbr: 'f',
    help: 'Path to worker snapshot JSON',
  );
  final observeDlqParser = observeParser.addCommand('dlq');
  observeDlqParser.addOption(
    'file',
    abbr: 'f',
    help: 'Path to DLQ snapshot JSON',
  );
  final schedulesParser = observeParser.addCommand('schedules');
  schedulesParser.addOption('file', abbr: 'f', help: 'Path to schedules file');

  parser.addCommand('observe', observeParser);
  final dlqList = dlqCommandParser.addCommand('list');
  dlqList
    ..addOption(
      'queue',
      abbr: 'q',
      valueHelp: 'queue',
      help: 'Dead letter queue name',
    )
    ..addOption(
      'limit',
      abbr: 'l',
      defaultsTo: '50',
      help: 'Maximum entries to return',
    )
    ..addOption('offset', defaultsTo: '0', help: 'Pagination offset')
    ..addOption(
      'since',
      help: 'Only include entries dead-lettered after timestamp (ISO8601)',
      valueHelp: 'timestamp',
    );
  final dlqShow = dlqCommandParser.addCommand('show');
  dlqShow
    ..addOption(
      'queue',
      abbr: 'q',
      valueHelp: 'queue',
      help: 'Dead letter queue name',
    )
    ..addOption('id', help: 'Task identifier', valueHelp: 'task-id');
  final dlqReplay = dlqCommandParser.addCommand('replay');
  dlqReplay
    ..addOption(
      'queue',
      abbr: 'q',
      valueHelp: 'queue',
      help: 'Dead letter queue name',
    )
    ..addOption(
      'limit',
      abbr: 'l',
      defaultsTo: '10',
      help: 'Maximum entries to replay',
    )
    ..addOption(
      'since',
      help: 'Only replay entries dead-lettered after timestamp (ISO8601)',
      valueHelp: 'timestamp',
    )
    ..addOption(
      'delay',
      help: 'Schedule replay with delay (e.g. 5s, 2m)',
      valueHelp: 'duration',
    )
    ..addFlag(
      'dry-run',
      defaultsTo: false,
      negatable: false,
      help: 'Preview entries without replaying',
    )
    ..addFlag(
      'yes',
      abbr: 'y',
      defaultsTo: false,
      negatable: false,
      help: 'Confirm replay without prompting',
    );
  final dlqPurge = dlqCommandParser.addCommand('purge');
  dlqPurge
    ..addOption(
      'queue',
      abbr: 'q',
      valueHelp: 'queue',
      help: 'Dead letter queue name',
    )
    ..addOption('limit', abbr: 'l', help: 'Remove at most this many entries')
    ..addOption(
      'since',
      help: 'Only purge entries dead-lettered after timestamp (ISO8601)',
      valueHelp: 'timestamp',
    )
    ..addFlag(
      'yes',
      abbr: 'y',
      defaultsTo: false,
      negatable: false,
      help: 'Confirm purge without prompting',
    );
  parser.addCommand('dlq', dlqCommandParser);

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

  if (command.name == 'dlq') {
    final sub = command.command;
    if (sub == null) {
      stdoutSink.writeln(_dlqUsage(dlqCommandParser));
      return 64;
    }
    final builder = contextBuilder ?? _createDefaultContext;
    late final CliContext ctx;
    try {
      ctx = await builder();
    } catch (error, stack) {
      stderrSink.writeln('Failed to initialize Stem context: $error');
      stderrSink.writeln(stack);
      return 70;
    }
    try {
      switch (sub.name) {
        case 'list':
          return _dlqList(ctx, sub, stdoutSink, stderrSink);
        case 'show':
          return _dlqShow(ctx, sub, stdoutSink, stderrSink);
        case 'replay':
          return _dlqReplay(ctx, sub, stdoutSink, stderrSink);
        case 'purge':
          return _dlqPurge(ctx, sub, stdoutSink, stderrSink);
        default:
          stderrSink.writeln('Unknown dlq subcommand: ${sub.name}');
          stdoutSink.writeln(_dlqUsage(dlqCommandParser));
          return 64;
      }
    } finally {
      await ctx.dispose();
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
String _dlqUsage(ArgParser parser) =>
    'Usage: stem dlq <subcommand>\n${parser.usage}';

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

Future<int> _dlqList(
  CliContext ctx,
  ArgResults args,
  StringSink out,
  StringSink err,
) async {
  final queue = _readQueueArg(args, err);
  if (queue == null) return 64;
  final limit = _parseIntWithDefault(
    args['limit'] as String?,
    'limit',
    err,
    fallback: 50,
    min: 1,
  );
  if (limit == null) return 64;
  final offset = _parseIntWithDefault(
    args['offset'] as String?,
    'offset',
    err,
    fallback: 0,
    min: 0,
  );
  if (offset == null) return 64;
  final sinceInput = args['since'] as String?;
  final since = _parseIsoTimestamp(sinceInput);
  if (sinceInput != null && since == null) {
    err.writeln('Invalid --since timestamp. Use ISO-8601 format.');
    return 64;
  }
  final page = await ctx.broker.listDeadLetters(
    queue,
    limit: limit,
    offset: offset,
  );
  var entries = page.entries;
  if (since != null) {
    entries = entries.where((e) => !e.deadAt.isBefore(since)).toList();
  }
  if (entries.isEmpty) {
    out.writeln('No dead letter entries found.');
    if (page.hasMore) {
      out.writeln('More entries available. Try --offset ${page.nextOffset}.');
    }
    return 0;
  }
  out.writeln(
    'ID                                  | Task                | Attempts | DeadAt                | Reason',
  );
  out.writeln(
    '------------------------------------+---------------------+---------+----------------------+----------------',
  );
  for (final entry in entries) {
    final idCell = _padCell(entry.envelope.id, 36);
    final taskCell = _padCell(entry.envelope.name, 19);
    final attemptsCell = _padCell(
      entry.envelope.attempt.toString(),
      7,
      alignRight: true,
    );
    final deadAtCell = _padCell(entry.deadAt.toIso8601String(), 20);
    final reasonCell = _padCell(entry.reason ?? '-', 16);
    out.writeln(
      '$idCell | $taskCell | $attemptsCell | $deadAtCell | $reasonCell',
    );
  }
  if (page.hasMore) {
    out.writeln('More entries available. Next offset: ${page.nextOffset}.');
  }
  return 0;
}

Future<int> _dlqShow(
  CliContext ctx,
  ArgResults args,
  StringSink out,
  StringSink err,
) async {
  final queue = _readQueueArg(args, err);
  if (queue == null) return 64;
  final id = (args['id'] as String?)?.trim();
  if (id == null || id.isEmpty) {
    err.writeln('Missing required --id option.');
    return 64;
  }
  final entry = await ctx.broker.getDeadLetter(queue, id);
  if (entry == null) {
    out.writeln('No dead letter entry found for id $id in $queue.');
    return 1;
  }
  final encoder = const JsonEncoder.withIndent('  ');
  final payload = {
    'queue': queue,
    'deadAt': entry.deadAt.toIso8601String(),
    'reason': entry.reason,
    'meta': entry.meta,
    'envelope': entry.envelope.toJson(),
  };
  out.writeln(encoder.convert(payload));
  return 0;
}

Future<int> _dlqReplay(
  CliContext ctx,
  ArgResults args,
  StringSink out,
  StringSink err,
) async {
  final queue = _readQueueArg(args, err);
  if (queue == null) return 64;
  final limit = _parseIntWithDefault(
    args['limit'] as String?,
    'limit',
    err,
    fallback: 10,
    min: 1,
  );
  if (limit == null) return 64;
  final sinceInput = args['since'] as String?;
  final since = _parseIsoTimestamp(sinceInput);
  if (sinceInput != null && since == null) {
    err.writeln('Invalid --since timestamp. Use ISO-8601 format.');
    return 64;
  }
  final delayInput = args['delay'] as String?;
  final delay = _parseOptionalDuration(delayInput);
  if (delayInput != null && delay == null) {
    err.writeln('Invalid --delay duration. Use values like 5s or 2m.');
    return 64;
  }
  final dryRun = args['dry-run'] as bool? ?? false;
  final confirmed = args['yes'] as bool? ?? false;
  if (!dryRun && !confirmed) {
    err.writeln('Replay requires --yes or use --dry-run to preview.');
    return 64;
  }
  final result = await ctx.broker.replayDeadLetters(
    queue,
    limit: limit,
    since: since,
    delay: delay,
    dryRun: dryRun,
  );
  if (result.entries.isEmpty) {
    out.writeln(
      dryRun
          ? 'No dead letter entries match the replay filters.'
          : 'No dead letter entries were replayed.',
    );
    return 0;
  }
  if (!result.dryRun) {
    await _annotateReplayMeta(ctx, result.entries, delay, err);
  }
  final verb = result.dryRun ? 'Would replay' : 'Replayed';
  out.writeln(
    '$verb ${result.entries.length} entr'
    '${result.entries.length == 1 ? 'y' : 'ies'} from $queue.',
  );
  final sample = result.entries.take(10).toList();
  for (final entry in sample) {
    out.writeln(
      ' - ${entry.envelope.id} (${entry.envelope.name}) '
      '[attempt ${entry.envelope.attempt}] reason=${entry.reason ?? '-'}',
    );
  }
  final remaining = result.entries.length - sample.length;
  if (remaining > 0) {
    out.writeln('   ... $remaining more');
  }
  return 0;
}

Future<int> _dlqPurge(
  CliContext ctx,
  ArgResults args,
  StringSink out,
  StringSink err,
) async {
  final queue = _readQueueArg(args, err);
  if (queue == null) return 64;
  final limit = _parseOptionalInt(
    args['limit'] as String?,
    'limit',
    err,
    min: 0,
  );
  if (args['limit'] != null && limit == null) return 64;
  final sinceInput = args['since'] as String?;
  final since = _parseIsoTimestamp(sinceInput);
  if (sinceInput != null && since == null) {
    err.writeln('Invalid --since timestamp. Use ISO-8601 format.');
    return 64;
  }
  final confirmed = args['yes'] as bool? ?? false;
  if (!confirmed) {
    err.writeln('Purge requires --yes confirmation.');
    return 64;
  }
  final removed = await ctx.broker.purgeDeadLetters(
    queue,
    since: since,
    limit: limit,
  );
  out.writeln(
    'Removed $removed dead letter entr'
    '${removed == 1 ? 'y' : 'ies'} from $queue.',
  );
  return 0;
}

Future<void> _annotateReplayMeta(
  CliContext ctx,
  List<DeadLetterEntry> entries,
  Duration? delay,
  StringSink err,
) async {
  final backend = ctx.backend;
  if (backend == null) return;
  final replayedAt = DateTime.now().toIso8601String();
  for (final entry in entries) {
    try {
      final status = await backend.get(entry.envelope.id);
      if (status == null) continue;
      final meta = Map<String, Object?>.from(status.meta)
        ..['lastReplayAt'] = replayedAt
        ..['replayCount'] =
            ((status.meta['replayCount'] as num?)?.toInt() ?? 0) + 1;
      if (entry.reason != null) {
        meta['lastReplayReason'] = entry.reason;
      }
      if (delay != null) {
        meta['lastReplayDelayMs'] = delay.inMilliseconds;
      }
      await backend.set(
        status.id,
        status.state,
        payload: status.payload,
        error: status.error,
        attempt: status.attempt,
        meta: meta,
      );
    } catch (error, stack) {
      err.writeln(
        'Failed to annotate replay metadata for ${entry.envelope.id}: $error',
      );
      err.writeln(stack);
    }
  }
}

Future<CliContext> _createDefaultContext() async {
  final config = StemConfig.fromEnvironment();
  final brokerUri = Uri.parse(config.brokerUrl);
  final disposables = <Future<void> Function()>[];
  late Broker broker;
  if (brokerUri.scheme == 'redis' || brokerUri.scheme == 'rediss') {
    final redisBroker = await RedisStreamsBroker.connect(config.brokerUrl);
    broker = redisBroker;
    disposables.add(() => redisBroker.close());
  } else if (brokerUri.scheme == 'memory') {
    final inMemory = InMemoryRedisBroker();
    broker = inMemory;
    disposables.add(() async => inMemory.dispose());
  } else {
    throw StateError('Unsupported broker scheme: ${brokerUri.scheme}');
  }

  ResultBackend? backend;
  final backendUrl = config.resultBackendUrl;
  if (backendUrl != null) {
    final backendUri = Uri.parse(backendUrl);
    if (backendUri.scheme == 'redis' || backendUri.scheme == 'rediss') {
      final redisBackend = await RedisResultBackend.connect(backendUrl);
      backend = redisBackend;
      disposables.add(() => redisBackend.close());
    } else if (backendUri.scheme == 'memory') {
      backend = InMemoryResultBackend();
    } else {
      throw StateError(
        'Unsupported result backend scheme: ${backendUri.scheme}',
      );
    }
  }

  return CliContext(
    broker: broker,
    backend: backend,
    dispose: () async {
      for (final disposer in disposables.reversed) {
        await disposer();
      }
    },
  );
}

String? _readQueueArg(ArgResults args, StringSink err) {
  final queue = (args['queue'] as String?)?.trim();
  if (queue == null || queue.isEmpty) {
    err.writeln('Missing required --queue option.');
    return null;
  }
  return queue;
}

int? _parseIntWithDefault(
  String? value,
  String option,
  StringSink err, {
  required int fallback,
  int min = 0,
}) {
  if (value == null) return fallback;
  final parsed = int.tryParse(value);
  if (parsed == null || parsed < min) {
    err.writeln('Invalid --$option value: $value');
    return null;
  }
  return parsed;
}

int? _parseOptionalInt(
  String? value,
  String option,
  StringSink err, {
  int min = 0,
}) {
  if (value == null) return null;
  final parsed = int.tryParse(value);
  if (parsed == null || parsed < min) {
    err.writeln('Invalid --$option value: $value');
    return null;
  }
  return parsed;
}

DateTime? _parseIsoTimestamp(String? value) {
  if (value == null) return null;
  try {
    return DateTime.parse(value);
  } catch (_) {
    return null;
  }
}

String _padCell(String value, int width, {bool alignRight = false}) {
  if (width <= 0) return '';
  var truncated = value;
  if (truncated.length > width) {
    truncated = width <= 3
        ? truncated.substring(0, width)
        : '${truncated.substring(0, width - 3)}...';
  }
  return alignRight ? truncated.padLeft(width) : truncated.padRight(width);
}

class CliContext {
  CliContext({required this.broker, this.backend, required this.dispose});

  final Broker broker;
  final ResultBackend? backend;
  final Future<void> Function() dispose;
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
