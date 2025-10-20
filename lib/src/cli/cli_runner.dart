import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:yaml/yaml.dart';
import 'package:redis/redis.dart';

import '../backend/in_memory_backend.dart';
import '../backend/redis_backend.dart';
import '../broker_redis/in_memory_broker.dart';
import '../broker_redis/redis_broker.dart';
import '../core/config.dart';
import '../core/contracts.dart';
import '../observability/metrics.dart';
import '../observability/snapshots.dart';
import '../observability/config.dart';
import '../observability/heartbeat.dart';
import '../scheduler/schedule_calculator.dart';
import '../scheduler/in_memory_schedule_store.dart';
import '../scheduler/redis_schedule_store.dart';
import 'file_schedule_repository.dart';

const _brokerEnvKey = 'STEM_BROKER_URL';
const _backendEnvKey = 'STEM_RESULT_BACKEND_URL';

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

  final showParser = scheduleParser.addCommand('show');
  showParser.addOption('id', abbr: 'i', help: 'Schedule identifier');

  final applyParser = scheduleParser.addCommand('apply');
  applyParser
    ..addOption(
      'file',
      abbr: 'f',
      valueHelp: 'path',
      help: 'Path to schedules YAML/JSON file',
    )
    ..addFlag(
      'dry-run',
      defaultsTo: false,
      negatable: false,
      help: 'Validate schedules without applying changes',
    )
    ..addFlag(
      'yes',
      abbr: 'y',
      defaultsTo: false,
      negatable: false,
      help: 'Apply without interactive confirmation',
    );

  final deleteParser = scheduleParser.addCommand('delete');
  deleteParser
    ..addOption('id', abbr: 'i', help: 'Schedule identifier')
    ..addFlag(
      'yes',
      abbr: 'y',
      defaultsTo: false,
      negatable: false,
      help: 'Confirm deletion without prompt',
    );

  final dryRunParser = scheduleParser.addCommand('dry-run');
  dryRunParser
    ..addOption('id', abbr: 'i', help: 'Schedule identifier')
    ..addOption('spec', help: 'Override schedule spec', valueHelp: 'spec')
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

  final workerParser = ArgParser();
  final workerStatusParser = workerParser.addCommand('status');
  workerStatusParser
    ..addMultiOption(
      'worker',
      abbr: 'w',
      help: 'Filter by worker identifier (repeatable).',
    )
    ..addFlag(
      'follow',
      abbr: 'f',
      defaultsTo: false,
      negatable: false,
      help: 'Stream live heartbeats from the broker.',
    )
    ..addFlag(
      'json',
      defaultsTo: false,
      negatable: false,
      help: 'Render heartbeat output as JSON.',
    )
    ..addOption(
      'namespace',
      defaultsTo: 'stem',
      help: 'Heartbeat namespace used by workers.',
    )
    ..addOption(
      'broker',
      help: 'Override broker URL (defaults to STEM_BROKER_URL).',
      valueHelp: 'redis://host:port',
    )
    ..addOption(
      'backend',
      help: 'Override result backend URL.',
      valueHelp: 'redis://host:port',
    )
    ..addOption(
      'timeout',
      defaultsTo: '30s',
      help: 'Follow mode timeout without heartbeat before exiting.',
      valueHelp: 'duration',
    )
    ..addOption(
      'heartbeat-interval',
      help: 'Expected heartbeat interval (e.g. 10s).',
      valueHelp: 'duration',
    )
    ..addOption(
      'metrics-exporters',
      help:
          'Comma separated metrics exporters (console,otlp:http://host,prometheus).',
    );
  parser.addCommand('worker', workerParser);

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
    late final ScheduleCliContext scheduleCtx;
    try {
      scheduleCtx = await _createScheduleCliContext(repoPath: scheduleFilePath);
    } catch (error, stack) {
      stderrSink.writeln('Failed to initialize schedule context: $error');
      stderrSink.writeln(stack);
      return 70;
    }

    try {
      switch (sub.name) {
        case 'list':
          return _scheduleList(scheduleCtx, stdoutSink);
        case 'show':
          return _scheduleShow(scheduleCtx, sub, stdoutSink, stderrSink);
        case 'apply':
          return _scheduleApply(
            scheduleCtx,
            sub,
            stdoutSink,
            stderrSink,
            scheduleFilePath,
          );
        case 'delete':
          return _scheduleDelete(scheduleCtx, sub, stdoutSink, stderrSink);
        case 'dry-run':
          return _scheduleDryRun(scheduleCtx, sub, stdoutSink, stderrSink);
        default:
          stderrSink.writeln('Unknown schedule subcommand: ${sub.name}');
          stdoutSink.writeln(_scheduleUsage(scheduleParser));
          return 64;
      }
    } finally {
      await scheduleCtx.dispose();
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

  if (command.name == 'worker') {
    final sub = command.command;
    if (sub == null) {
      stderrSink.writeln('Usage: stem worker status [options]');
      return 64;
    }
    switch (sub.name) {
      case 'status':
        CliContext? ctx;
        if (contextBuilder != null) {
          try {
            ctx = await contextBuilder();
          } catch (error, stack) {
            stderrSink.writeln('Failed to initialize Stem context: $error');
            stderrSink.writeln(stack);
            return 70;
          }
        }
        try {
          return _workerStatus(sub, stdoutSink, stderrSink, context: ctx);
        } finally {
          await ctx?.dispose();
        }
      default:
        stderrSink.writeln('Unknown worker subcommand: ${sub.name}');
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

Future<int> _scheduleList(ScheduleCliContext ctx, StringSink out) async {
  final entries = ctx.store != null
      ? await ctx.store!.list()
      : await ctx.repo!.load();
  if (entries.isEmpty) {
    out.writeln('No schedules found.');
    return 0;
  }
  final calculator = ScheduleCalculator();
  final now = DateTime.now();
  out.writeln(
    'ID        | Task           | Queue    | Spec             | Next Run                | Last Run                | Jitter  | Enabled',
  );
  out.writeln(
    '----------+----------------+----------+------------------+------------------------+------------------------+---------+---------',
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
    out.writeln(
      '${_padCell(entry.id, 10)}| '
      '${_padCell(entry.taskName, 16)}| '
      '${_padCell(entry.queue, 10)}| '
      '${_padCell(entry.spec, 18)}| '
      '${_padCell(_formatDateTime(next), 24)}| '
      '${_padCell(_formatDateTime(entry.lastRunAt), 24)}| '
      '${_padCell(_formatDuration(entry.jitter), 7)} | '
      '${entry.enabled ? 'yes' : 'no'}',
    );
  }
  return 0;
}

Future<int> _scheduleShow(
  ScheduleCliContext ctx,
  ArgResults args,
  StringSink out,
  StringSink err,
) async {
  final id =
      args['id'] as String? ?? (args.rest.isNotEmpty ? args.rest.first : null);
  if (id == null || id.isEmpty) {
    err.writeln(
      'Missing schedule identifier (use --id or positional argument).',
    );
    return 64;
  }
  ScheduleEntry? entry;
  if (ctx.store != null) {
    entry = await ctx.store!.get(id);
  } else {
    entry = _findScheduleById(await ctx.repo!.load(), id);
  }
  if (entry == null) {
    err.writeln('Schedule "$id" not found.');
    return 64;
  }
  final encoder = const JsonEncoder.withIndent('  ');
  out.writeln(encoder.convert(entry.toJson()));
  return 0;
}

Future<int> _scheduleApply(
  ScheduleCliContext ctx,
  ArgResults args,
  StringSink out,
  StringSink err,
  String? defaultFile,
) async {
  final definitionsPath = args['file'] as String? ?? defaultFile;
  if (definitionsPath == null) {
    err.writeln('Missing --file pointing to schedule definitions.');
    return 64;
  }
  final dryRun = args['dry-run'] as bool? ?? false;
  final confirmed = args['yes'] as bool? ?? false;
  if (!dryRun && !confirmed) {
    err.writeln('Apply requires --yes confirmation (or use --dry-run).');
    return 64;
  }
  if (!File(definitionsPath).existsSync()) {
    err.writeln('Definitions file not found: $definitionsPath');
    return 64;
  }

  List<Map<String, Object?>> raw;
  try {
    raw = _loadScheduleDefinitions(definitionsPath);
  } catch (error) {
    err.writeln('Failed to parse definitions: $error');
    return 64;
  }
  final entries = <ScheduleEntry>[];
  for (final map in raw) {
    try {
      final entry = _definitionToEntry(map);
      _validateScheduleEntry(entry);
      entries.add(entry);
    } catch (error) {
      err.writeln(error.toString());
      return 64;
    }
  }

  if (dryRun) {
    out.writeln('Validated ${entries.length} schedule(s).');
    return 0;
  }

  if (ctx.store != null) {
    for (final entry in entries) {
      await ctx.store!.upsert(entry);
    }
  } else {
    final repo = ctx.repo!;
    final existing = await repo.load();
    final byId = {for (final entry in existing) entry.id: entry};
    for (final entry in entries) {
      byId[entry.id] = entry;
    }
    await repo.save(byId.values.toList());
  }

  out.writeln('Applied ${entries.length} schedule(s).');
  return 0;
}

Future<int> _scheduleDelete(
  ScheduleCliContext ctx,
  ArgResults args,
  StringSink out,
  StringSink err,
) async {
  final id =
      args['id'] as String? ?? (args.rest.isNotEmpty ? args.rest.first : null);
  if (id == null || id.isEmpty) {
    err.writeln(
      'Missing schedule identifier (use --id or positional argument).',
    );
    return 64;
  }
  final confirmed = args['yes'] as bool? ?? false;
  if (!confirmed) {
    err.writeln('Deletion requires --yes confirmation.');
    return 64;
  }
  if (ctx.store != null) {
    await ctx.store!.remove(id);
  } else {
    final repo = ctx.repo!;
    final entries = await repo.load();
    final filtered = entries.where((e) => e.id != id).toList();
    if (filtered.length == entries.length) {
      err.writeln('Schedule "$id" not found.');
      return 64;
    }
    await repo.save(filtered);
  }
  out.writeln('Deleted schedule "$id".');
  return 0;
}

Future<int> _scheduleDryRun(
  ScheduleCliContext ctx,
  ArgResults args,
  StringSink out,
  StringSink err,
) async {
  final id =
      args['id'] as String? ?? (args.rest.isNotEmpty ? args.rest.first : null);
  final spec = args['spec'] as String?;
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

  ScheduleEntry? entry;
  if (ctx.store != null && id != null) {
    entry = await ctx.store!.get(id);
  } else if (ctx.repo != null && id != null) {
    entry = _findScheduleById(await ctx.repo!.load(), id);
  }

  if (entry == null && spec == null) {
    err.writeln('Provide an existing schedule id or --spec to evaluate.');
    return 64;
  }

  entry ??= ScheduleEntry(
    id: '_dry_',
    taskName: '_dry_',
    queue: 'default',
    spec: spec!,
  );

  final calculator = ScheduleCalculator(random: Random(0));
  var current = entry.copyWith(lastRunAt: start);
  for (var i = 0; i < count; i++) {
    final next = calculator.nextRun(current, start, includeJitter: true);
    out.writeln(next.toIso8601String());
    current = current.copyWith(lastRunAt: next);
    start = next;
  }
  return 0;
}

List<Map<String, Object?>> _loadScheduleDefinitions(String path) {
  final contents = File(path).readAsStringSync();
  dynamic decoded;
  try {
    decoded = jsonDecode(contents);
  } catch (_) {
    final yamlDoc = loadYaml(contents);
    decoded = jsonDecode(jsonEncode(yamlDoc));
  }
  if (decoded is Map && decoded['schedules'] != null) {
    decoded = decoded['schedules'];
  }
  if (decoded is! List) {
    throw FormatException('Schedule definitions must be provided as a list.');
  }
  return decoded.map<Map<String, Object?>>((item) {
    if (item is Map) {
      return _coerceMap(item);
    }
    throw FormatException('Schedule definition entries must be objects.');
  }).toList();
}

ScheduleEntry _definitionToEntry(Map<String, Object?> def) {
  final id = (def['id'] ?? def['name']) as String?;
  if (id == null || id.isEmpty) {
    throw FormatException('Schedule entry is missing an "id" field.');
  }
  final task = (def['task'] ?? def['taskName']) as String?;
  if (task == null || task.isEmpty) {
    throw FormatException('Schedule "$id" missing "task" field.');
  }
  final spec = (def['schedule'] ?? def['spec']) as String?;
  if (spec == null || spec.isEmpty) {
    throw FormatException('Schedule "$id" missing "schedule" field.');
  }
  final queue = (def['queue'] as String?) ?? 'default';
  final enabled = def['enabled'] is bool ? def['enabled'] as bool : true;
  final args = def['args'] is Map
      ? _coerceMap(def['args'] as Map)
      : const <String, Object?>{};
  final meta = def['meta'] is Map
      ? _coerceMap(def['meta'] as Map)
      : const <String, Object?>{};

  Duration? jitter;
  if (def['jitterMs'] != null) {
    final jitterMs = (def['jitterMs'] as num).toInt();
    if (jitterMs < 0) {
      throw FormatException('Schedule "$id" has negative jitter.');
    }
    jitter = Duration(milliseconds: jitterMs);
  } else if (def['jitter'] is String) {
    jitter = _parseOptionalDuration(def['jitter'] as String?);
  }

  DateTime? lastRunAt;
  if (def['lastRunAt'] is String && (def['lastRunAt'] as String).isNotEmpty) {
    lastRunAt = DateTime.parse(def['lastRunAt'] as String);
  }
  DateTime? nextRunAt;
  if (def['nextRunAt'] is String && (def['nextRunAt'] as String).isNotEmpty) {
    nextRunAt = DateTime.parse(def['nextRunAt'] as String);
  }
  Duration? lastJitter;
  if (def['lastJitterMs'] != null) {
    lastJitter = Duration(milliseconds: (def['lastJitterMs'] as num).toInt());
  }
  final lastError = def['lastError'] as String?;
  final timezone = def['timezone'] as String?;

  return ScheduleEntry(
    id: id,
    taskName: task,
    queue: queue,
    spec: spec,
    args: args,
    enabled: enabled,
    jitter: jitter,
    lastRunAt: lastRunAt,
    nextRunAt: nextRunAt,
    lastJitter: lastJitter,
    lastError: lastError?.isEmpty == true ? null : lastError,
    timezone: timezone,
    meta: meta,
  );
}

Map<String, Object?> _coerceMap(Map<dynamic, dynamic> input) {
  final result = <String, Object?>{};
  input.forEach((key, value) {
    result[key.toString()] = _coerceValue(value);
  });
  return result;
}

Object? _coerceValue(Object? value) {
  if (value is Map) {
    return _coerceMap(value);
  }
  if (value is List) {
    return value.map(_coerceValue).toList();
  }
  return value;
}

ScheduleEntry? _findScheduleById(List<ScheduleEntry> entries, String id) {
  for (final entry in entries) {
    if (entry.id == id) {
      return entry;
    }
  }
  return null;
}

void _validateScheduleEntry(ScheduleEntry entry) {
  final calculator = ScheduleCalculator();
  try {
    final base = entry.lastRunAt ?? DateTime.now();
    final next = calculator.nextRun(entry, base, includeJitter: false);
    final interval = next.difference(base);
    if (interval <= Duration.zero) {
      throw FormatException('computed non-positive interval');
    }
    if (interval < const Duration(seconds: 1)) {
      throw FormatException('interval must be >= 1 second');
    }
    if (entry.jitter != null && entry.jitter! > interval) {
      throw FormatException('configured jitter exceeds interval');
    }
  } catch (error) {
    throw FormatException('Schedule "${entry.id}": $error');
  }
}

String _formatDateTime(DateTime? value) => value?.toIso8601String() ?? '-';
String _formatDuration(Duration? value) =>
    value != null ? '${value.inMilliseconds}ms' : '-';

class ScheduleCliContext {
  ScheduleCliContext.store({
    required ScheduleStore storeInstance,
    Future<void> Function()? dispose,
  }) : store = storeInstance,
       repo = null,
       _dispose = dispose ?? (() async {});

  ScheduleCliContext.file({FileScheduleRepository? repo})
    : store = null,
      repo = repo ?? FileScheduleRepository(),
      _dispose = (() async {});

  final ScheduleStore? store;
  final FileScheduleRepository? repo;
  final Future<void> Function() _dispose;

  Future<void> dispose() => _dispose();
}

Future<ScheduleCliContext> _createScheduleCliContext({String? repoPath}) async {
  final url = Platform.environment['STEM_SCHEDULE_STORE_URL']?.trim();
  if (url == null || url.isEmpty) {
    return ScheduleCliContext.file(
      repo: FileScheduleRepository(path: repoPath),
    );
  }

  final uri = Uri.parse(url);
  final disposables = <Future<void> Function()>[];
  ScheduleStore store;
  switch (uri.scheme) {
    case 'redis':
    case 'rediss':
      final redisStore = await RedisScheduleStore.connect(url);
      store = redisStore;
      disposables.add(() => redisStore.close());
      break;
    case 'memory':
      store = InMemoryScheduleStore();
      break;
    default:
      throw StateError('Unsupported schedule store scheme: ${uri.scheme}');
  }

  return ScheduleCliContext.store(
    storeInstance: store,
    dispose: () async {
      for (final disposer in disposables.reversed) {
        await disposer();
      }
    },
  );
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
    StemMetrics.instance.increment(
      'stem.replay.count',
      tags: {'queue': queue},
      value: result.entries.length,
    );
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
    final redisBroker = await RedisStreamsBroker.connect(
      config.brokerUrl,
      tls: config.tls,
    );
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

Future<int> _workerStatus(
  ArgResults args,
  StringSink out,
  StringSink err, {
  CliContext? context,
}) async {
  final namespaceInput = (args['namespace'] as String?)?.trim();
  final filters = ((args['worker'] as List?) ?? const [])
      .cast<String>()
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet();
  final follow = args['follow'] as bool? ?? false;
  final jsonOutput = args['json'] as bool? ?? false;
  final heartbeatInterval =
      ObservabilityConfig.parseDuration(
        args['heartbeat-interval'] as String?,
      ) ??
      const Duration(seconds: 10);
  final timeout =
      ObservabilityConfig.parseDuration(args['timeout'] as String?) ??
      const Duration(seconds: 30);
  final exportersOverride = args['metrics-exporters'] as String?;
  if (exportersOverride != null && exportersOverride.trim().isNotEmpty) {
    final exporters = exportersOverride
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
    ObservabilityConfig(metricExporters: exporters).applyMetricExporters();
  }

  final env = Platform.environment;
  final brokerUrl = (args['broker'] as String?) ?? env[_brokerEnvKey] ?? '';
  final backendUrl = (args['backend'] as String?) ?? env[_backendEnvKey];
  final namespace = namespaceInput == null || namespaceInput.isEmpty
      ? 'stem'
      : namespaceInput;

  if (follow) {
    if (brokerUrl.isEmpty) {
      err.writeln(
        'Broker URL is required for follow mode (set STEM_BROKER_URL or use --broker).',
      );
      return 64;
    }
    return _streamHeartbeats(
      brokerUrl,
      namespace,
      filters,
      timeout,
      heartbeatInterval,
      jsonOutput,
      out,
      err,
    );
  }

  return _printHeartbeatSnapshot(
    backendUrl,
    namespace,
    filters,
    jsonOutput,
    heartbeatInterval,
    out,
    err,
    contextBackend: context?.backend,
  );
}

Future<int> _streamHeartbeats(
  String brokerUrl,
  String namespace,
  Set<String> filters,
  Duration timeout,
  Duration expectedInterval,
  bool jsonOutput,
  StringSink out,
  StringSink err,
) async {
  final uri = Uri.parse(brokerUrl);
  if (uri.scheme != 'redis' && uri.scheme != 'rediss') {
    err.writeln('Heartbeat streaming requires a Redis broker.');
    return 64;
  }

  late final _PubSubHandle handle;
  try {
    handle = await _connectPubSub(uri);
  } catch (error) {
    err.writeln('Failed to connect to broker: $error');
    return 70;
  }

  final channel = WorkerHeartbeat.topic(namespace);
  final stream = handle.stream;
  final completer = Completer<int>();
  late final StreamSubscription<List> subscription;
  Timer? timeoutTimer;

  void startTimer() {
    if (timeout <= Duration.zero) return;
    timeoutTimer?.cancel();
    timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        err.writeln(
          'No heartbeat received within ${_formatReadableDuration(timeout)} '
          '(channel: $channel).',
        );
        completer.complete(1);
      }
      subscription.cancel();
    });
  }

  subscription = stream.listen(
    (message) {
      if (message.length < 3) {
        return;
      }
      if (message[0] != 'message') return;
      final payload = message[2];
      if (payload is! String) return;
      try {
        final json = jsonDecode(payload) as Map<String, Object?>;
        final heartbeat = WorkerHeartbeat.fromJson(json);
        if (heartbeat.namespace != namespace) return;
        if (filters.isNotEmpty && !filters.contains(heartbeat.workerId)) return;
        startTimer();
        _renderHeartbeat(
          heartbeat,
          out,
          jsonOutput: jsonOutput,
          expectedInterval: expectedInterval,
        );
      } catch (error) {
        err.writeln('Failed to parse heartbeat payload: $error');
      }
    },
    onError: (error) {
      if (!completer.isCompleted) {
        err.writeln('Heartbeat stream error: $error');
        completer.complete(70);
      }
    },
    onDone: () {
      if (!completer.isCompleted) {
        completer.complete(0);
      }
    },
  );

  startTimer();

  handle.pubSub.subscribe([channel]);
  final code = await completer.future;
  final timer = timeoutTimer;
  if (timer != null) {
    timer.cancel();
  }
  await subscription.cancel();
  await handle.close(channel: channel);
  return code;
}

Future<int> _printHeartbeatSnapshot(
  String? backendUrl,
  String namespace,
  Set<String> filters,
  bool jsonOutput,
  Duration expectedInterval,
  StringSink out,
  StringSink err, {
  ResultBackend? contextBackend,
}) async {
  late final ResultBackend backend;
  _BackendHandle? handle;
  if (contextBackend != null) {
    backend = contextBackend;
  } else {
    if (backendUrl == null || backendUrl.isEmpty) {
      err.writeln(
        'Result backend URL is required for snapshot mode (set STEM_RESULT_BACKEND_URL or use --backend).',
      );
      return 64;
    }
    try {
      handle = await _connectBackend(backendUrl);
      backend = handle.backend;
    } catch (error) {
      err.writeln('Failed to connect to result backend: $error');
      return 70;
    }
  }

  try {
    final snapshots = await backend.listWorkerHeartbeats();
    final filtered = snapshots.where((heartbeat) {
      if (heartbeat.namespace != namespace) return false;
      if (filters.isNotEmpty && !filters.contains(heartbeat.workerId)) {
        return false;
      }
      return true;
    }).toList()..sort((a, b) => a.workerId.compareTo(b.workerId));
    if (filtered.isEmpty) {
      out.writeln('No worker heartbeats found for namespace "$namespace".');
      return 0;
    }
    for (final heartbeat in filtered) {
      _renderHeartbeat(
        heartbeat,
        out,
        jsonOutput: jsonOutput,
        expectedInterval: expectedInterval,
      );
    }
    return 0;
  } finally {
    await handle?.dispose?.call();
  }
}

void _renderHeartbeat(
  WorkerHeartbeat heartbeat,
  StringSink out, {
  required bool jsonOutput,
  Duration? expectedInterval,
}) {
  if (jsonOutput) {
    out.writeln(jsonEncode(heartbeat.toJson()));
    return;
  }
  final now = DateTime.now().toUtc();
  final age = now.difference(heartbeat.timestamp);
  final isStale = expectedInterval != null && expectedInterval > Duration.zero
      ? age > expectedInterval
      : false;
  out.writeln(
    'Worker ${heartbeat.workerId} '
    '(namespace: ${heartbeat.namespace}) '
    '@ ${heartbeat.timestamp.toIso8601String()} '
    'isolate=${heartbeat.isolateCount} inflight=${heartbeat.inflight}'
    '${isStale ? ' [stale ${_formatReadableDuration(age)}]' : ''}',
  );
  if (heartbeat.lastLeaseRenewal != null) {
    out.writeln(
      '  lastLeaseRenewal: '
      '${heartbeat.lastLeaseRenewal!.toIso8601String()}',
    );
  }
  if (heartbeat.queues.isNotEmpty) {
    out.writeln('  queues:');
    for (final queue in heartbeat.queues) {
      out.writeln('    - ${queue.name}: inflight=${queue.inflight}');
    }
  }
  out.writeln('');
}

String _formatReadableDuration(Duration duration) {
  if (duration.inSeconds == 0) {
    return '${duration.inMilliseconds}ms';
  }
  if (duration.inMinutes >= 1) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return seconds == 0 ? '${minutes}m' : '${minutes}m${seconds}s';
  }
  return '${duration.inSeconds}s';
}

Future<_BackendHandle> _connectBackend(String url) async {
  final uri = Uri.parse(url);
  switch (uri.scheme) {
    case 'redis':
    case 'rediss':
      final backend = await RedisResultBackend.connect(url);
      return _BackendHandle(backend: backend, dispose: () => backend.close());
    case 'memory':
      final backend = InMemoryResultBackend();
      return _BackendHandle(backend: backend);
    default:
      throw StateError('Unsupported backend scheme: ${uri.scheme}');
  }
}

Future<_PubSubHandle> _connectPubSub(Uri uri) async {
  if (uri.scheme != 'redis' && uri.scheme != 'rediss') {
    throw StateError('Unsupported broker scheme: ${uri.scheme}');
  }
  final host = uri.host.isNotEmpty ? uri.host : 'localhost';
  final port = uri.hasPort ? uri.port : 6379;
  final connection = RedisConnection();
  final command = await connection.connect(host, port);

  if (uri.userInfo.isNotEmpty) {
    final parts = uri.userInfo.split(':');
    final password = parts.length == 2 ? parts[1] : parts[0];
    await command.send_object(['AUTH', password]);
  }

  if (uri.pathSegments.isNotEmpty) {
    final db = int.tryParse(uri.pathSegments.first);
    if (db != null) {
      await command.send_object(['SELECT', db]);
    }
  }

  final pubSub = PubSub(command);
  return _PubSubHandle(connection, command, pubSub);
}

class _BackendHandle {
  _BackendHandle({required this.backend, this.dispose});

  final ResultBackend backend;
  final Future<void> Function()? dispose;
}

class _PubSubHandle {
  _PubSubHandle(this.connection, this.command, this.pubSub);

  final RedisConnection connection;
  final Command command;
  final PubSub pubSub;

  Stream<List> get stream => pubSub.getStream().cast<List>();

  Future<void> close({String? channel}) async {
    if (channel != null) {
      try {
        pubSub.unsubscribe([channel]);
      } catch (_) {}
    }
    await connection.close();
  }
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
