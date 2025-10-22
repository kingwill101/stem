import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/command_runner.dart';
import 'package:stem/src/cli/dependencies.dart';
import 'package:stem/src/cli/utilities.dart';
import 'package:yaml/yaml.dart';

import '../core/contracts.dart';
import '../scheduler/schedule_calculator.dart';
import '../scheduler/schedule_spec.dart';
import 'file_schedule_repository.dart';

class ScheduleCommand extends Command<int> {
  ScheduleCommand(this.dependencies) {
    addSubcommand(ScheduleListCommand(dependencies));
    addSubcommand(ScheduleShowCommand(dependencies));
    addSubcommand(ScheduleApplyCommand(dependencies));
    addSubcommand(ScheduleDeleteCommand(dependencies));
    addSubcommand(ScheduleEnableCommand(dependencies));
    addSubcommand(ScheduleDisableCommand(dependencies));
    addSubcommand(ScheduleDryRunCommand(dependencies));
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'schedule';

  @override
  final String description = 'Manage periodic task schedules.';

  @override
  Future<int> run() async {
    throw UsageException('Specify a schedule subcommand.', usage);
  }
}

class ScheduleListCommand extends Command<int> {
  ScheduleListCommand(this.dependencies);

  final StemCommandDependencies dependencies;

  @override
  final String name = 'list';

  @override
  final String description = 'List configured schedules.';

  @override
  Future<int> run() async {
    final scheduleCtx = await dependencies.createScheduleContext();
    try {
      final entries = scheduleCtx.store != null
          ? await scheduleCtx.store!.list()
          : await scheduleCtx.repo!.load();
      if (entries.isEmpty) {
        dependencies.out.writeln('No schedules found.');
        return 0;
      }
      final calculator = ScheduleCalculator();
      final now = DateTime.now();
      dependencies.out.writeln(
        'ID        | Task           | Queue    | Spec             | Next Run                | Last Run                | Jitter  | Enabled',
      );
      dependencies.out.writeln(
        '----------+----------------+----------+------------------+------------------------+------------------------+---------+---------',
      );
      for (final entry in entries) {
        final reference = entry.lastRunAt ?? now;
        final next = entry.nextRunAt ??
            calculator.nextRun(
              entry.copyWith(lastRunAt: reference),
              reference,
              includeJitter: false,
            );
        dependencies.out.writeln(
          '${padCell(entry.id, 10)}| '
          '${padCell(entry.taskName, 16)}| '
          '${padCell(entry.queue, 10)}| '
          '${padCell(_describeSpec(entry.spec), 18)}| '
          '${padCell(formatDateTime(next), 24)}| '
          '${padCell(formatDateTime(entry.lastRunAt), 24)}| '
          '${padCell(formatDuration(entry.jitter), 7)} | '
          '${entry.enabled ? 'yes' : 'no'}',
        );
      }
      return 0;
    } finally {
      await scheduleCtx.dispose();
    }
  }
}

class ScheduleShowCommand extends Command<int> {
  ScheduleShowCommand(this.dependencies) {
    argParser.addOption('id', abbr: 'i', help: 'Schedule identifier');
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'show';

  @override
  final String description = 'Display details for a schedule entry.';

  @override
  Future<int> run() async {
    final scheduleCtx = await dependencies.createScheduleContext();
    try {
      final args = argResults!;
      final id = args['id'] as String? ??
          (args.rest.isNotEmpty ? args.rest.first : null);
      if (id == null || id.isEmpty) {
        dependencies.err.writeln(
          'Missing schedule identifier (use --id or positional argument).',
        );
        return 64;
      }
      ScheduleEntry? entry;
      if (scheduleCtx.store != null) {
        entry = await scheduleCtx.store!.get(id);
      } else {
        final list = await scheduleCtx.repo!.load();
        for (final e in list) {
          if (e.id == id) {
            entry = e;
            break;
          }
        }
      }
      if (entry == null) {
        dependencies.err.writeln('Schedule "$id" not found.');
        return 64;
      }
      final encoder = const JsonEncoder.withIndent('  ');
      dependencies.out.writeln(encoder.convert(entry.toJson()));
      return 0;
    } finally {
      await scheduleCtx.dispose();
    }
  }
}

class ScheduleApplyCommand extends Command<int> {
  ScheduleApplyCommand(this.dependencies) {
    argParser
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
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'apply';

  @override
  final String description = 'Apply schedules from a file or input.';

  @override
  Future<int> run() async {
    final scheduleCtx = await dependencies.createScheduleContext();
    try {
      final args = argResults!;
      final definitionsPath =
          args['file'] as String? ?? dependencies.scheduleFilePath;
      if (definitionsPath == null) {
        dependencies.err
            .writeln('Missing --file pointing to schedule definitions.');
        return 64;
      }
      final dryRun = args['dry-run'] as bool? ?? false;
      final confirmed = args['yes'] as bool? ?? false;
      if (!dryRun && !confirmed) {
        dependencies.err
            .writeln('Apply requires --yes confirmation (or use --dry-run).');
        return 64;
      }
      if (!File(definitionsPath).existsSync()) {
        dependencies.err
            .writeln('Definitions file not found: $definitionsPath');
        return 64;
      }

      List<Map<String, Object?>> raw;
      try {
        raw = _loadScheduleDefinitions(definitionsPath);
      } catch (error) {
        dependencies.err.writeln('Failed to parse definitions: $error');
        return 64;
      }
      final entries = <ScheduleEntry>[];
      for (final map in raw) {
        try {
          final entry = _definitionToEntry(map);
          _validateScheduleEntry(entry);
          entries.add(entry);
        } catch (error) {
          dependencies.err.writeln(error.toString());
          return 64;
        }
      }

      if (dryRun) {
        dependencies.out.writeln('Validated ${entries.length} schedule(s).');
        return 0;
      }

      if (scheduleCtx.store != null) {
        for (final entry in entries) {
          await scheduleCtx.store!.upsert(entry);
        }
      } else {
        final repo = scheduleCtx.repo!;
        final existing = await repo.load();
        final byId = {for (final entry in existing) entry.id: entry};
        for (final entry in entries) {
          byId[entry.id] = entry;
        }
        await repo.save(byId.values.toList());
      }

      dependencies.out.writeln('Applied ${entries.length} schedule(s).');
      return 0;
    } finally {
      await scheduleCtx.dispose();
    }
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
      throw const FormatException(
          'Schedule definitions must be provided as a list.');
    }
    return decoded.map<Map<String, Object?>>((item) {
      if (item is Map) {
        return _coerceMap(item);
      }
      throw const FormatException(
          'Schedule definition entries must be objects.');
    }).toList();
  }

  ScheduleEntry _definitionToEntry(Map<String, Object?> def) {
    final id = (def['id'] ?? def['name']) as String?;
    if (id == null || id.isEmpty) {
      throw const FormatException('Schedule entry is missing an "id" field.');
    }
    final task = (def['task'] ?? def['taskName']) as String?;
    if (task == null || task.isEmpty) {
      throw FormatException('Schedule "$id" missing "task" field.');
    }
    final specRaw = def['schedule'] ?? def['spec'];
    if (specRaw == null) {
      throw FormatException('Schedule "$id" missing "schedule" field.');
    }
    final scheduleSpec = ScheduleSpec.fromPersisted(specRaw);
    final queue = (def['queue'] as String?) ?? 'default';
    final enabledValue = def['enabled'];
    final enabled = enabledValue is bool ? enabledValue : true;
    final rawArgs = def['args'];
    final args =
        rawArgs is Map ? _coerceMap(rawArgs) : const <String, Object?>{};
    final rawKwargs = def['kwargs'];
    final kwargs =
        rawKwargs is Map ? _coerceMap(rawKwargs) : const <String, Object?>{};
    final rawMeta = def['meta'];
    final meta =
        rawMeta is Map ? _coerceMap(rawMeta) : const <String, Object?>{};

    Duration? jitter;
    if (def['jitterMs'] != null) {
      final jitterMs = (def['jitterMs'] as num).toInt();
      if (jitterMs < 0) {
        throw FormatException('Schedule "$id" has negative jitter.');
      }
      jitter = Duration(milliseconds: jitterMs);
    } else if (def['jitter'] is String) {
      jitter = parseOptionalDuration(def['jitter'] as String?);
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
      spec: scheduleSpec,
      args: args,
      kwargs: kwargs,
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

  void _validateScheduleEntry(ScheduleEntry entry) {
    final calculator = ScheduleCalculator();
    try {
      final base = entry.lastRunAt ?? DateTime.now();
      final next = calculator.nextRun(entry, base, includeJitter: false);
      final interval = next.difference(base);
      if (interval <= Duration.zero) {
        throw const FormatException('computed non-positive interval');
      }
      if (interval < const Duration(seconds: 1)) {
        throw const FormatException('interval must be >= 1 second');
      }
      if (entry.jitter != null && entry.jitter! > interval) {
        throw const FormatException('configured jitter exceeds interval');
      }
    } catch (error) {
      throw FormatException('Schedule "${entry.id}": $error');
    }
  }

  Map<String, Object?> _coerceMap(Map input) {
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
}

String _describeSpec(ScheduleSpec spec) {
  switch (spec) {
    case IntervalScheduleSpec interval:
      final base = 'every ${interval.every.inSeconds}s';
      final start = interval.startAt != null
          ? ' from ${interval.startAt!.toIso8601String()}'
          : '';
      final end = interval.endAt != null
          ? ' until ${interval.endAt!.toIso8601String()}'
          : '';
      return '$base$start$end';
    case CronScheduleSpec cron:
      return cron.expression;
    case SolarScheduleSpec solar:
      final offset =
          solar.offset != null ? ' (${solar.offset!.inMinutes}m offset)' : '';
      return '${solar.event} @${solar.latitude.toStringAsFixed(2)},${solar.longitude.toStringAsFixed(2)}$offset';
    case ClockedScheduleSpec clocked:
      return 'once ${clocked.runAt.toIso8601String()}';
    case CalendarScheduleSpec calendar:
      return 'calendar ${calendar.toJson()}';
  }
}

class ScheduleDeleteCommand extends Command<int> {
  ScheduleDeleteCommand(this.dependencies) {
    argParser
      ..addOption('id', abbr: 'i', help: 'Schedule identifier')
      ..addFlag(
        'yes',
        abbr: 'y',
        defaultsTo: false,
        negatable: false,
        help: 'Confirm deletion without prompt',
      );
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'delete';

  @override
  final String description = 'Delete a schedule entry.';

  @override
  Future<int> run() async {
    final scheduleCtx = await dependencies.createScheduleContext();
    try {
      final args = argResults!;
      final id = args['id'] as String? ??
          (args.rest.isNotEmpty ? args.rest.first : null);
      if (id == null || id.isEmpty) {
        dependencies.err.writeln(
          'Missing schedule identifier (use --id or positional argument).',
        );
        return 64;
      }
      final confirmed = args['yes'] as bool? ?? false;
      if (!confirmed) {
        dependencies.err.writeln('Deletion requires --yes confirmation.');
        return 64;
      }
      if (scheduleCtx.store != null) {
        await scheduleCtx.store!.remove(id);
      } else {
        final repo = scheduleCtx.repo!;
        final entries = await repo.load();
        final filtered = entries.where((e) => e.id != id).toList();
        if (filtered.length == entries.length) {
          dependencies.err.writeln('Schedule "$id" not found.');
          return 64;
        }
        await repo.save(filtered);
      }
      dependencies.out.writeln('Deleted schedule "$id".');
      return 0;
    } finally {
      await scheduleCtx.dispose();
    }
  }
}

class ScheduleEnableCommand extends Command<int> {
  ScheduleEnableCommand(this.dependencies) {
    argParser.addOption('id', abbr: 'i', help: 'Schedule identifier');
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'enable';

  @override
  final String description = 'Enable a schedule entry.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final id = args['id'] as String? ??
        (args.rest.isNotEmpty ? args.rest.first : null);
    if (id == null || id.isEmpty) {
      dependencies.err
          .writeln('Provide a schedule id via --id or positional argument.');
      return 64;
    }
    final scheduleCtx = await dependencies.createScheduleContext();
    try {
      if (scheduleCtx.store != null) {
        final existing = await scheduleCtx.store!.get(id);
        if (existing == null) {
          dependencies.err.writeln('Schedule "$id" not found.');
          return 64;
        }
        final updated =
            existing.copyWith(enabled: true, nextRunAt: null, lastError: null);
        await scheduleCtx.store!.upsert(updated);
        dependencies.out.writeln('Enabled schedule "$id".');
        return 0;
      }
      final repo = scheduleCtx.repo;
      if (repo != null) {
        final entries = await repo.load();
        final index = entries.indexWhere((entry) => entry.id == id);
        if (index == -1) {
          dependencies.err.writeln('Schedule "$id" not found.');
          return 64;
        }
        final updated = entries[index]
            .copyWith(enabled: true, nextRunAt: null, lastError: null);
        entries[index] = updated;
        await repo.save(entries);
        dependencies.out.writeln('Enabled schedule "$id".');
        return 0;
      }
      dependencies.err.writeln('No schedule store configured.');
      return 64;
    } finally {
      await scheduleCtx.dispose();
    }
  }
}

class ScheduleDisableCommand extends Command<int> {
  ScheduleDisableCommand(this.dependencies) {
    argParser.addOption('id', abbr: 'i', help: 'Schedule identifier');
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'disable';

  @override
  final String description = 'Disable a schedule entry.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final id = args['id'] as String? ??
        (args.rest.isNotEmpty ? args.rest.first : null);
    if (id == null || id.isEmpty) {
      dependencies.err
          .writeln('Provide a schedule id via --id or positional argument.');
      return 64;
    }
    final scheduleCtx = await dependencies.createScheduleContext();
    try {
      if (scheduleCtx.store != null) {
        final existing = await scheduleCtx.store!.get(id);
        if (existing == null) {
          dependencies.err.writeln('Schedule "$id" not found.');
          return 64;
        }
        final updated = existing.copyWith(enabled: false);
        await scheduleCtx.store!.upsert(updated);
        dependencies.out.writeln('Disabled schedule "$id".');
        return 0;
      }
      final repo = scheduleCtx.repo;
      if (repo != null) {
        final entries = await repo.load();
        final index = entries.indexWhere((entry) => entry.id == id);
        if (index == -1) {
          dependencies.err.writeln('Schedule "$id" not found.');
          return 64;
        }
        entries[index] = entries[index].copyWith(enabled: false);
        await repo.save(entries);
        dependencies.out.writeln('Disabled schedule "$id".');
        return 0;
      }
      dependencies.err.writeln('No schedule store configured.');
      return 64;
    } finally {
      await scheduleCtx.dispose();
    }
  }
}

class ScheduleDryRunCommand extends Command<int> {
  ScheduleDryRunCommand(this.dependencies) {
    argParser
      ..addOption('id', abbr: 'i', help: 'Schedule identifier')
      ..addOption('spec', help: 'Override schedule spec', valueHelp: 'spec')
      ..addOption(
        'count',
        help: 'Number of occurrences to preview',
        defaultsTo: '5',
      )
      ..addOption(
        'from',
        help: 'Start timestamp ISO8601',
        valueHelp: 'time',
      );
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'dry-run';

  @override
  final String description = 'Preview upcoming fire times for a schedule.';

  @override
  Future<int> run() async {
    final scheduleCtx = await dependencies.createScheduleContext();
    try {
      final args = argResults!;
      final id = args['id'] as String? ??
          (args.rest.isNotEmpty ? args.rest.first : null);
      final specInput = args['spec'] as String?;
      final overrideSpec =
          specInput != null ? ScheduleSpec.fromPersisted(specInput) : null;
      final count = int.tryParse(args['count'] as String? ?? '5') ?? 5;
      DateTime start;
      if (args['from'] != null) {
        try {
          start = DateTime.parse(args['from'] as String);
        } catch (_) {
          dependencies.err
              .writeln('Invalid --from timestamp. Use ISO-8601 format.');
          return 64;
        }
      } else {
        start = DateTime.now();
      }

      ScheduleEntry? entry;
      if (scheduleCtx.store != null && id != null) {
        entry = await scheduleCtx.store!.get(id);
      } else if (scheduleCtx.repo != null && id != null) {
        final list = await scheduleCtx.repo!.load();
        for (final e in list) {
          if (e.id == id) {
            entry = e;
            break;
          }
        }
      }

      if (entry == null && overrideSpec == null) {
        dependencies.err
            .writeln('Provide an existing schedule id or --spec to evaluate.');
        return 64;
      }

      entry ??= ScheduleEntry(
        id: '_dry_',
        taskName: '_dry_',
        queue: 'default',
        spec: overrideSpec!,
      );

      final calculator = ScheduleCalculator(random: Random(0));
      var current = entry.copyWith(lastRunAt: start);
      for (var i = 0; i < count; i++) {
        final next = calculator.nextRun(current, start, includeJitter: true);
        dependencies.out.writeln(next.toIso8601String());
        current = current.copyWith(lastRunAt: next);
        start = next;
      }
      return 0;
    } finally {
      await scheduleCtx.dispose();
    }
  }
}

class ScheduleCliContext {
  ScheduleCliContext.store({
    required ScheduleStore storeInstance,
    Future<void> Function()? dispose,
  })  : store = storeInstance,
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
