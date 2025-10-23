import 'dart:convert';

import 'package:stem/src/cli/cli_runner.dart' show CliContext;
import 'package:stem/src/cli/utilities.dart';
import 'package:stem/stem.dart';
import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:stem/src/cli/cli_runner.dart';
import 'package:stem/src/cli/dependencies.dart';

class DlqCommand extends Command<int> {
  DlqCommand(this.dependencies) {
    addSubcommand(DlqListCommand(dependencies));
    addSubcommand(DlqShowCommand(dependencies));
    addSubcommand(DlqReplayCommand(dependencies));
    addSubcommand(DlqPurgeCommand(dependencies));
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'dlq';

  @override
  final String description = 'Manage dead-letter queues.';

  @override
  Future<int> run() async {
    throw UsageException('Specify a dlq subcommand.', usage);
  }
}

class DlqListCommand extends Command<int> {
  DlqListCommand(this.dependencies) {
    argParser
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
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'list';

  @override
  final String description = 'List dead-letter queue entries.';

  @override
  Future<int> run() async {
    late final CliContext ctx;
    try {
      ctx = await dependencies.createCliContext();
    } catch (error, stack) {
      dependencies.err.writeln('Failed to initialize Stem context: $error');
      dependencies.err.writeln(stack);
      return 70;
    }
    try {
      final args = argResults!;
      final out = dependencies.out;
      final err = dependencies.err;

      final queue = readQueueArg(args, err);
      if (queue == null) return 64;

      final limit = parseIntWithDefault(
        args['limit'] as String?,
        'limit',
        err,
        fallback: 50,
        min: 1,
      );
      if (limit == null) return 64;

      final offset = parseIntWithDefault(
        args['offset'] as String?,
        'offset',
        err,
        fallback: 0,
        min: 0,
      );
      if (offset == null) return 64;

      final sinceInput = args['since'] as String?;
      final since = parseIsoTimestamp(sinceInput);
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
          out.writeln(
            'More entries available. Try --offset ${page.nextOffset}.',
          );
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
        final idCell = padCell(entry.envelope.id, 36);
        final taskCell = padCell(entry.envelope.name, 19);
        final attemptsCell = padCell(
          entry.envelope.attempt.toString(),
          7,
          alignRight: true,
        );
        final deadAtCell = padCell(entry.deadAt.toIso8601String(), 20);
        final reasonCell = padCell(entry.reason ?? '-', 16);
        out.writeln(
          '$idCell | $taskCell | $attemptsCell | $deadAtCell | $reasonCell',
        );
      }
      if (page.hasMore) {
        out.writeln('More entries available. Next offset: ${page.nextOffset}.');
      }
      return 0;
    } finally {
      await ctx.dispose();
    }
  }
}

class DlqShowCommand extends Command<int> {
  DlqShowCommand(this.dependencies) {
    argParser
      ..addOption(
        'queue',
        abbr: 'q',
        valueHelp: 'queue',
        help: 'Dead letter queue name',
      )
      ..addOption('id', help: 'Task identifier', valueHelp: 'task-id');
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'show';

  @override
  final String description = 'Show details for a dead-letter entry.';

  @override
  Future<int> run() async {
    late final CliContext ctx;
    try {
      ctx = await dependencies.createCliContext();
    } catch (error, stack) {
      dependencies.err.writeln('Failed to initialize Stem context: $error');
      dependencies.err.writeln(stack);
      return 70;
    }
    try {
      final args = argResults!;
      final out = dependencies.out;
      final err = dependencies.err;

      final queue = readQueueArg(args, err);
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
    } finally {
      await ctx.dispose();
    }
  }
}

class DlqReplayCommand extends Command<int> {
  DlqReplayCommand(this.dependencies) {
    argParser
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
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'replay';

  @override
  final String description = 'Replay entries from the dead-letter queue.';

  @override
  Future<int> run() async {
    late final CliContext ctx;
    try {
      ctx = await dependencies.createCliContext();
    } catch (error, stack) {
      dependencies.err.writeln('Failed to initialize Stem context: $error');
      dependencies.err.writeln(stack);
      return 70;
    }
    try {
      final args = argResults!;
      final out = dependencies.out;
      final err = dependencies.err;

      final queue = readQueueArg(args, err);
      if (queue == null) return 64;

      final limit = parseIntWithDefault(
        args['limit'] as String?,
        'limit',
        err,
        fallback: 10,
        min: 1,
      );
      if (limit == null) return 64;

      final sinceInput = args['since'] as String?;
      final since = parseIsoTimestamp(sinceInput);
      if (sinceInput != null && since == null) {
        err.writeln('Invalid --since timestamp. Use ISO-8601 format.');
        return 64;
      }

      final delayInput = args['delay'] as String?;
      final delay = parseOptionalDuration(delayInput);
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
        final backend = ctx.backend;
        if (backend != null) {
          final replayedAt = DateTime.now().toIso8601String();
          for (final entry in result.entries) {
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
    } finally {
      await ctx.dispose();
    }
  }
}

class DlqPurgeCommand extends Command<int> {
  DlqPurgeCommand(this.dependencies) {
    argParser
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
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'purge';

  @override
  final String description = 'Delete entries from the dead-letter queue.';

  @override
  Future<int> run() async {
    late final CliContext ctx;
    try {
      ctx = await dependencies.createCliContext();
    } catch (error, stack) {
      dependencies.err.writeln('Failed to initialize Stem context: $error');
      dependencies.err.writeln(stack);
      return 70;
    }
    try {
      final args = argResults!;
      final out = dependencies.out;
      final err = dependencies.err;

      final queue = readQueueArg(args, err);
      if (queue == null) return 64;

      final limit = parseOptionalInt(
        args['limit'] as String?,
        'limit',
        err,
        min: 0,
      );
      if (args['limit'] != null && limit == null) return 64;

      final sinceInput = args['since'] as String?;
      final since = parseIsoTimestamp(sinceInput);
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
    } finally {
      await ctx.dispose();
    }
  }
}
