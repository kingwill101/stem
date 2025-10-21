import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:redis/redis.dart' as redis;
import 'package:path/path.dart' as p;
import 'package:stem/src/cli/cli_runner.dart';
import 'package:stem/src/cli/dependencies.dart';
import 'package:stem/src/cli/utilities.dart';
import 'package:stem/src/control/control_messages.dart';
import 'package:stem/src/control/revoke_store.dart';
import 'package:stem/stem.dart';

class WorkerCommand extends Command<int> {
  WorkerCommand(this.dependencies) {
    addSubcommand(WorkerPingCommand(dependencies));
    addSubcommand(WorkerInspectCommand(dependencies));
    addSubcommand(WorkerRevokeCommand(dependencies));
    addSubcommand(WorkerStatsCommand(dependencies));
    addSubcommand(WorkerStatusCommand(dependencies));
    addSubcommand(WorkerShutdownCommand(dependencies));
    addSubcommand(WorkerHealthcheckCommand(dependencies));
    addSubcommand(WorkerDiagnoseCommand(dependencies));
    addSubcommand(WorkerMultiCommand(dependencies));
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'worker';

  @override
  final String description = 'Inspect or control worker processes.';

  @override
  Future<int> run() async {
    throw UsageException('Specify a worker subcommand.', usage);
  }
}

class WorkerPingCommand extends Command<int> {
  WorkerPingCommand(this.dependencies) {
    argParser
      ..addMultiOption(
        'worker',
        abbr: 'w',
        help: 'Target worker identifier (repeatable).',
      )
      ..addOption(
        'namespace',
        defaultsTo: 'stem',
        help: 'Control namespace used for worker IDs.',
      )
      ..addOption(
        'timeout',
        defaultsTo: '5s',
        help: 'Wait duration for replies (e.g. 3s, 1m).',
        valueHelp: 'duration',
      )
      ..addFlag(
        'json',
        defaultsTo: false,
        negatable: false,
        help: 'Emit replies as JSON instead of text.',
      );
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'ping';

  @override
  final String description = 'Send ping control messages to workers.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final namespaceInput = (args['namespace'] as String?)?.trim();
    final namespace = namespaceInput == null || namespaceInput.isEmpty
        ? 'stem'
        : namespaceInput;
    final timeout =
        ObservabilityConfig.parseDuration(args['timeout'] as String?) ??
            const Duration(seconds: 5);
    final jsonOutput = args['json'] as bool? ?? false;
    final targets = ((args['worker'] as List?) ?? const [])
        .cast<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();

    late CliContext ctx;
    try {
      ctx = await dependencies.createCliContext();
    } catch (error, stack) {
      dependencies.err.writeln('Failed to initialize Stem context: $error');
      dependencies.err.writeln(stack);
      return 70;
    }

    try {
      final requestId = generateEnvelopeId();
      final command = ControlCommandMessage(
        requestId: requestId,
        type: 'ping',
        targets: targets.isEmpty ? const ['*'] : targets.toList(),
        timeoutMs: timeout.inMilliseconds,
      );

      await _publishControlCommand(
        ctx,
        namespace: namespace,
        targets: targets,
        command: command,
      );

      final replies = await _collectControlReplies(
        ctx,
        namespace: namespace,
        requestId: requestId,
        expectedWorkers: targets.isEmpty ? null : targets.length,
        timeout: timeout,
      );

      if (jsonOutput) {
        final data = replies.map((reply) => reply.toMap()).toList();
        dependencies.out.writeln(jsonEncode(data));
      } else {
        if (targets.isNotEmpty) {
          final missing = targets.difference(
            replies.map((reply) => reply.workerId).toSet(),
          );
          if (missing.isNotEmpty) {
            dependencies.err.writeln(
              'No reply from: ${missing.join(', ')}',
            );
          }
        }

        if (replies.isEmpty) {
          dependencies.out.writeln(
            'No replies received within ${timeout.inMilliseconds}ms.',
          );
        } else {
          dependencies.out.writeln('Worker        | Status | Message');
          dependencies.out.writeln('--------------+--------+----------------');
          for (final reply in replies) {
            final message = reply.status == 'ok'
                ? (reply.payload['timestamp'] ?? '-')
                : (reply.error?['message'] ?? '-');
            dependencies.out.writeln(
              '${reply.workerId.padRight(14)}| '
              '${reply.status.padRight(6)} | '
              '$message',
            );
          }
        }
      }
      final hasError = replies.any((reply) => reply.status != 'ok');
      return hasError ? 70 : 0;
    } finally {
      await ctx.dispose();
    }
  }
}

class WorkerInspectCommand extends Command<int> {
  WorkerInspectCommand(this.dependencies) {
    argParser
      ..addMultiOption(
        'worker',
        abbr: 'w',
        help: 'Target worker identifier (repeatable).',
      )
      ..addOption(
        'namespace',
        defaultsTo: 'stem',
        help: 'Control namespace used for worker IDs.',
      )
      ..addOption(
        'timeout',
        defaultsTo: '5s',
        help: 'Wait duration for replies (e.g. 3s, 1m).',
        valueHelp: 'duration',
      )
      ..addFlag(
        'json',
        defaultsTo: false,
        negatable: false,
        help: 'Emit replies as JSON instead of text.',
      )
      ..addFlag(
        'include-revoked',
        defaultsTo: true,
        help: 'Include revoked task metadata in the response.',
      );
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'inspect';

  @override
  final String description =
      'Inspect in-flight tasks and revocations for workers.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final namespaceInput = (args['namespace'] as String?)?.trim();
    final namespace = namespaceInput == null || namespaceInput.isEmpty
        ? 'stem'
        : namespaceInput;
    final timeout =
        ObservabilityConfig.parseDuration(args['timeout'] as String?) ??
            const Duration(seconds: 5);
    final jsonOutput = args['json'] as bool? ?? false;
    final includeRevoked = args['include-revoked'] as bool? ?? true;
    final targets = ((args['worker'] as List?) ?? const [])
        .cast<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();

    late CliContext ctx;
    try {
      ctx = await dependencies.createCliContext();
    } catch (error, stack) {
      dependencies.err.writeln('Failed to initialize Stem context: $error');
      dependencies.err.writeln(stack);
      return 70;
    }

    try {
      final requestId = generateEnvelopeId();
      final command = ControlCommandMessage(
        requestId: requestId,
        type: 'inspect',
        targets: targets.isEmpty ? const ['*'] : targets.toList(),
        timeoutMs: timeout.inMilliseconds,
        payload: {
          'namespace': namespace,
          'includeRevoked': includeRevoked,
        },
      );

      await _publishControlCommand(
        ctx,
        namespace: namespace,
        targets: targets,
        command: command,
      );

      final replies = await _collectControlReplies(
        ctx,
        namespace: namespace,
        requestId: requestId,
        expectedWorkers: targets.isEmpty ? null : targets.length,
        timeout: timeout,
      );

      if (jsonOutput) {
        dependencies.out.writeln(
          jsonEncode(replies.map((reply) => reply.toMap()).toList()),
        );
      } else {
        _emitMissingWarnings(
          targets,
          replies.map((r) => r.workerId).toSet(),
        );
        if (replies.isEmpty) {
          dependencies.out.writeln(
            'No replies received within ${timeout.inMilliseconds}ms.',
          );
          return 70;
        }
        _renderInspectReplies(replies);
      }

      final hasError = replies.any((reply) => reply.status != 'ok');
      return hasError ? 70 : 0;
    } finally {
      await ctx.dispose();
    }
  }

  void _emitMissingWarnings(Set<String> targets, Set<String> responders) {
    if (targets.isEmpty) return;
    final missing = targets.difference(responders);
    if (missing.isEmpty) return;
    dependencies.err.writeln('No reply from: ${missing.join(', ')}');
  }

  void _renderInspectReplies(List<ControlReplyMessage> replies) {
    final ordered = [...replies]
      ..sort((a, b) => a.workerId.compareTo(b.workerId));
    for (var index = 0; index < ordered.length; index += 1) {
      final reply = ordered[index];
      dependencies.out.writeln(
        '${reply.workerId} (${reply.status})',
      );
      if (reply.status != 'ok') {
        final message = reply.error?['message'] ?? '-';
        dependencies.out.writeln('  error: $message');
      } else {
        final payload = reply.payload;
        final inflight = payload['inflight'];
        dependencies.out.writeln(
          '  inflight: ${inflight ?? 0}',
        );

        final active = payload['active'];
        if (active is List && active.isNotEmpty) {
          dependencies.out.writeln('  active tasks (${active.length}):');
          for (final task in active.cast<Map>()) {
            final id = task['id'] ?? '-';
            final name = task['task'] ?? '-';
            final queue = task['queue'] ?? '-';
            final attempt = task['attempt'];
            final runtimeMs = task['runtimeMs'];
            final runtime = runtimeMs is num
                ? formatReadableDuration(
                    Duration(milliseconds: runtimeMs.toInt()),
                  )
                : '-';
            dependencies.out.writeln(
              '    - $name ($id) queue=$queue attempt=${attempt ?? '-'} runtime=$runtime',
            );
          }
        } else {
          dependencies.out.writeln('  active tasks: none');
        }

        final revoked = payload['revoked'];
        if (revoked is List && revoked.isNotEmpty) {
          dependencies.out.writeln('  revoked cache (${revoked.length}):');
          for (final entry in revoked.cast<Map>()) {
            final taskId = entry['taskId'] ?? '-';
            final reason = entry['reason'] ?? '-';
            final requestedBy = entry['requestedBy'] ?? '-';
            dependencies.out.writeln(
              '    - $taskId reason=$reason requestedBy=$requestedBy',
            );
          }
        }
      }
      if (index < ordered.length - 1) {
        dependencies.out.writeln();
      }
    }
  }
}

class WorkerStatsCommand extends Command<int> {
  WorkerStatsCommand(this.dependencies) {
    argParser
      ..addMultiOption(
        'worker',
        abbr: 'w',
        help: 'Target worker identifier (repeatable).',
      )
      ..addOption(
        'namespace',
        defaultsTo: 'stem',
        help: 'Control namespace used for worker IDs.',
      )
      ..addOption(
        'timeout',
        defaultsTo: '5s',
        help: 'Wait duration for replies (e.g. 3s, 1m).',
        valueHelp: 'duration',
      )
      ..addFlag(
        'json',
        defaultsTo: false,
        negatable: false,
        help: 'Emit replies as JSON instead of text.',
      );
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'stats';

  @override
  final String description = 'Fetch runtime statistics from workers.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final namespaceInput = (args['namespace'] as String?)?.trim();
    final namespace = namespaceInput == null || namespaceInput.isEmpty
        ? 'stem'
        : namespaceInput;
    final timeout =
        ObservabilityConfig.parseDuration(args['timeout'] as String?) ??
            const Duration(seconds: 5);
    final jsonOutput = args['json'] as bool? ?? false;
    final targets = ((args['worker'] as List?) ?? const [])
        .cast<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();

    late CliContext ctx;
    try {
      ctx = await dependencies.createCliContext();
    } catch (error, stack) {
      dependencies.err.writeln('Failed to initialize Stem context: $error');
      dependencies.err.writeln(stack);
      return 70;
    }

    try {
      final requestId = generateEnvelopeId();
      final command = ControlCommandMessage(
        requestId: requestId,
        type: 'stats',
        targets: targets.isEmpty ? const ['*'] : targets.toList(),
        timeoutMs: timeout.inMilliseconds,
      );

      await _publishControlCommand(
        ctx,
        namespace: namespace,
        targets: targets,
        command: command,
      );

      final replies = await _collectControlReplies(
        ctx,
        namespace: namespace,
        requestId: requestId,
        expectedWorkers: targets.isEmpty ? null : targets.length,
        timeout: timeout,
      );

      if (jsonOutput) {
        dependencies.out.writeln(
          jsonEncode(replies.map((reply) => reply.toMap()).toList()),
        );
      } else {
        _emitMissingWarnings(targets, replies.map((r) => r.workerId).toSet());

        if (replies.isEmpty) {
          dependencies.out.writeln(
            'No replies received within ${timeout.inMilliseconds}ms.',
          );
          return 70;
        }

        final ordered = [...replies]
          ..sort((a, b) => a.workerId.compareTo(b.workerId));
        for (var index = 0; index < ordered.length; index += 1) {
          final reply = ordered[index];
          dependencies.out.writeln(
            '${reply.workerId} (${reply.status})',
          );
          if (reply.status == 'ok') {
            _renderStatsPayload(reply.payload);
          } else {
            final message = reply.error?['message'] ?? '-';
            dependencies.out.writeln('  error: $message');
          }
          if (index < ordered.length - 1) {
            dependencies.out.writeln();
          }
        }
      }

      return replies.isEmpty ? 70 : 0;
    } finally {
      await ctx.dispose();
    }
  }

  void _emitMissingWarnings(Set<String> targets, Set<String> responders) {
    if (targets.isEmpty) return;
    final missing = targets.difference(responders);
    if (missing.isEmpty) return;
    dependencies.err.writeln('No reply from: ${missing.join(', ')}');
  }

  void _renderStatsPayload(Map<String, Object?> payload) {
    final inflight = payload['inflight'];
    final concurrency = payload['concurrency'];
    final prefetch = payload['prefetch'];
    final timestamp = payload['timestamp'];
    final namespace = payload['namespace'];
    final queueName = payload['queue'];
    final host = payload['host'];
    final pid = payload['pid'];
    final lastQueueDepth = payload['lastQueueDepth'];
    final lastLeaseMs = payload['lastLeaseRenewalMsAgo'];

    dependencies.out.writeln(
      '  namespace: ${namespace ?? '-'} queue: ${queueName ?? '-'}',
    );
    dependencies.out.writeln(
      '  host: ${host ?? '-'} pid: ${pid ?? '-'}',
    );
    dependencies.out.writeln(
      '  inflight: ${inflight ?? '-'} / concurrency: ${concurrency ?? '-'} (prefetch: ${prefetch ?? '-'})',
    );

    if (timestamp is String && timestamp.isNotEmpty) {
      dependencies.out.writeln('  timestamp: $timestamp');
    }
    if (lastQueueDepth != null) {
      dependencies.out.writeln('  lastQueueDepth: $lastQueueDepth');
    }
    if (lastLeaseMs is num) {
      final duration = Duration(milliseconds: lastLeaseMs.toInt());
      dependencies.out.writeln(
        '  lastLeaseRenewal: ${formatReadableDuration(duration)} ago',
      );
    }

    final queues = payload['queues'];
    if (queues is Map && queues.isNotEmpty) {
      final parts = queues.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join(', ');
      dependencies.out.writeln('  queues: $parts');
    }

    final active = payload['active'];
    if (active is List && active.isNotEmpty) {
      dependencies.out.writeln('  active (${active.length}):');
      for (final task in active) {
        if (task is! Map) continue;
        final taskName = task['task'] ?? task['id'] ?? '-';
        final queue = task['queue'] ?? '-';
        final attempt = task['attempt'];
        final runtimeMs = task['runtimeMs'];
        final startedAt = task['startedAt'];
        final runtime = runtimeMs is num
            ? formatReadableDuration(
                Duration(milliseconds: runtimeMs.toInt()),
              )
            : '-';
        dependencies.out.writeln(
          '    - $taskName [queue=$queue, attempt=${attempt ?? '-'}, runtime=$runtime, started=$startedAt]',
        );
      }
    } else {
      dependencies.out.writeln('  active: none');
    }
  }
}

class WorkerRevokeCommand extends Command<int> {
  WorkerRevokeCommand(this.dependencies) {
    argParser
      ..addMultiOption(
        'task',
        abbr: 't',
        help: 'Task identifier to revoke (repeatable).',
        valueHelp: 'task-id',
      )
      ..addMultiOption(
        'worker',
        abbr: 'w',
        help: 'Optional worker identifier to target directly (repeatable).',
      )
      ..addOption(
        'namespace',
        defaultsTo: 'stem',
        help: 'Control namespace used for revocation records.',
      )
      ..addOption(
        'timeout',
        defaultsTo: '5s',
        help: 'Wait duration for worker acknowledgements.',
        valueHelp: 'duration',
      )
      ..addOption(
        'expires-in',
        help: 'Optional TTL for the revoke (e.g. 5m, 1h).',
        valueHelp: 'duration',
      )
      ..addOption(
        'reason',
        help: 'Optional human-readable reason for audit logs.',
      )
      ..addOption(
        'requester',
        help: 'Identifier for the requester (defaults to stem-cli).',
      )
      ..addFlag(
        'terminate',
        defaultsTo: false,
        negatable: false,
        help: 'Request workers to terminate tasks if currently running.',
      )
      ..addFlag(
        'json',
        defaultsTo: false,
        negatable: false,
        help: 'Emit replies as JSON instead of text.',
      );
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'revoke';

  @override
  final String description =
      'Persist and broadcast revoke commands for one or more tasks.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final tasks = ((args['task'] as List?) ?? const [])
        .cast<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (tasks.isEmpty) {
      dependencies.err.writeln(
        'At least one --task must be provided for revoke.',
      );
      return 64;
    }

    final namespaceInput = (args['namespace'] as String?)?.trim();
    final namespace = namespaceInput == null || namespaceInput.isEmpty
        ? 'stem'
        : namespaceInput;
    final timeout =
        ObservabilityConfig.parseDuration(args['timeout'] as String?) ??
            const Duration(seconds: 5);
    final reason = (args['reason'] as String?)?.trim();
    final requester = (args['requester'] as String?)?.trim().isNotEmpty == true
        ? (args['requester'] as String).trim()
        : 'stem-cli';
    final terminate = args['terminate'] as bool? ?? false;
    final jsonOutput = args['json'] as bool? ?? false;
    final expiresIn = parseOptionalDuration(args['expires-in'] as String?);
    final targets = ((args['worker'] as List?) ?? const [])
        .cast<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();

    late CliContext ctx;
    try {
      ctx = await dependencies.createCliContext();
    } catch (error, stack) {
      dependencies.err.writeln('Failed to initialize Stem context: $error');
      dependencies.err.writeln(stack);
      return 70;
    }

    try {
      final store = ctx.revokeStore;
      if (store == null) {
        dependencies.err.writeln(
          'No revoke store configured. Set STEM_REVOKE_STORE_URL or result backend.',
        );
        return 70;
      }

      final now = DateTime.now().toUtc();
      final baseVersion = generateRevokeVersion();
      final entries = <RevokeEntry>[];
      for (var i = 0; i < tasks.length; i += 1) {
        final taskId = tasks[i];
        entries.add(
          RevokeEntry(
            namespace: namespace,
            taskId: taskId,
            version: baseVersion + i,
            issuedAt: now,
            terminate: terminate,
            reason: reason,
            requestedBy: requester,
            expiresAt: expiresIn != null ? now.add(expiresIn) : null,
          ),
        );
      }

      await store.upsertAll(entries);
      await store.pruneExpired(namespace, now);

      final requestId = generateEnvelopeId();
      final command = ControlCommandMessage(
        requestId: requestId,
        type: 'revoke',
        targets: targets.isEmpty ? const ['*'] : targets.toList(),
        timeoutMs: timeout.inMilliseconds,
        payload: {
          'namespace': namespace,
          'requester': requester,
          'revocations': entries.map((entry) => entry.toJson()).toList(),
        },
      );

      await _publishControlCommand(
        ctx,
        namespace: namespace,
        targets: targets,
        command: command,
      );

      final replies = await _collectControlReplies(
        ctx,
        namespace: namespace,
        requestId: requestId,
        expectedWorkers: targets.isEmpty ? null : targets.length,
        timeout: timeout,
      );

      if (jsonOutput) {
        dependencies.out.writeln(
          jsonEncode(replies.map((reply) => reply.toMap()).toList()),
        );
      } else {
        _emitMissingWarnings(
          targets,
          replies.map((r) => r.workerId).toSet(),
        );
        if (replies.isEmpty) {
          dependencies.out.writeln(
            'No replies received within ${timeout.inMilliseconds}ms.',
          );
          return 70;
        }
        _renderRevokeReplies(replies);
      }

      final hasError = replies.any((reply) => reply.status != 'ok');
      return hasError ? 70 : 0;
    } finally {
      await ctx.dispose();
    }
  }

  void _emitMissingWarnings(Set<String> targets, Set<String> responders) {
    if (targets.isEmpty) return;
    final missing = targets.difference(responders);
    if (missing.isEmpty) return;
    dependencies.err.writeln('No reply from: ${missing.join(', ')}');
  }

  void _renderRevokeReplies(List<ControlReplyMessage> replies) {
    final ordered = [...replies]
      ..sort((a, b) => a.workerId.compareTo(b.workerId));
    for (var index = 0; index < ordered.length; index += 1) {
      final reply = ordered[index];
      dependencies.out.writeln(
        '${reply.workerId} (${reply.status})',
      );
      if (reply.status != 'ok') {
        final message = reply.error?['message'] ?? '-';
        dependencies.out.writeln('  error: $message');
      } else {
        final payload = reply.payload;
        final tasks = (payload['tasks'] as List?)?.cast<String>() ?? const [];
        final inflight =
            (payload['inflight'] as List?)?.cast<String>() ?? const [];
        final ignored =
            (payload['ignored'] as List?)?.cast<String>() ?? const [];
        final expired =
            (payload['expired'] as List?)?.cast<String>() ?? const [];
        dependencies.out.writeln(
          '  revoked: ${tasks.length} -> ${tasks.isEmpty ? '-' : tasks.join(', ')}',
        );
        if (inflight.isNotEmpty) {
          dependencies.out.writeln(
            '  inflight: ${inflight.join(', ')}',
          );
        }
        if (ignored.isNotEmpty) {
          dependencies.out.writeln(
            '  ignored: ${ignored.join(', ')}',
          );
        }
        if (expired.isNotEmpty) {
          dependencies.out.writeln(
            '  expired: ${expired.join(', ')}',
          );
        }
      }
      if (index < ordered.length - 1) {
        dependencies.out.writeln();
      }
    }
  }
}

class WorkerShutdownCommand extends Command<int> {
  WorkerShutdownCommand(this.dependencies) {
    argParser
      ..addMultiOption(
        'worker',
        abbr: 'w',
        help: 'Target worker identifier (repeatable).',
      )
      ..addOption(
        'namespace',
        defaultsTo: 'stem',
        help: 'Control namespace used for worker identifiers.',
      )
      ..addOption(
        'mode',
        defaultsTo: 'warm',
        allowed: const ['warm', 'soft', 'hard'],
        help: 'Shutdown mode to request (warm, soft, or hard).',
      )
      ..addOption(
        'timeout',
        defaultsTo: '5s',
        help: 'Wait duration for replies (e.g. 3s, 1m).',
        valueHelp: 'duration',
      )
      ..addFlag(
        'json',
        defaultsTo: false,
        negatable: false,
        help: 'Emit replies as JSON instead of text.',
      );
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'shutdown';

  @override
  final String description =
      'Request warm, soft, or hard shutdown for one or more workers.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final namespaceInput = (args['namespace'] as String?)?.trim();
    final namespace = namespaceInput == null || namespaceInput.isEmpty
        ? 'stem'
        : namespaceInput;
    final mode = ((args['mode'] as String?) ?? 'warm').trim().toLowerCase();
    final timeout =
        ObservabilityConfig.parseDuration(args['timeout'] as String?) ??
            const Duration(seconds: 5);
    final jsonOutput = args['json'] as bool? ?? false;
    final targets = ((args['worker'] as List?) ?? const [])
        .cast<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();

    late CliContext ctx;
    try {
      ctx = await dependencies.createCliContext();
    } catch (error, stack) {
      dependencies.err.writeln('Failed to initialize Stem context: $error');
      dependencies.err.writeln(stack);
      return 70;
    }

    try {
      final requestId = generateEnvelopeId();
      final command = ControlCommandMessage(
        requestId: requestId,
        type: 'shutdown',
        targets: targets.isEmpty ? const ['*'] : targets.toList(),
        timeoutMs: timeout.inMilliseconds,
        payload: {'mode': mode},
      );

      await _publishControlCommand(
        ctx,
        namespace: namespace,
        targets: targets,
        command: command,
      );

      final replies = await _collectControlReplies(
        ctx,
        namespace: namespace,
        requestId: requestId,
        expectedWorkers: targets.isEmpty ? null : targets.length,
        timeout: timeout,
      );

      if (jsonOutput) {
        dependencies.out.writeln(
          jsonEncode(replies.map((reply) => reply.toMap()).toList()),
        );
      } else {
        if (targets.isNotEmpty) {
          final missing = targets.difference(
            replies.map((reply) => reply.workerId).toSet(),
          );
          if (missing.isNotEmpty) {
            dependencies.err.writeln(
              'No reply from: ${missing.join(', ')}',
            );
          }
        }
        if (replies.isEmpty) {
          dependencies.out.writeln(
            'No replies received within ${timeout.inMilliseconds}ms.',
          );
          return 70;
        }
        dependencies.out.writeln('Worker        | Status | Mode  | Active');
        dependencies.out.writeln('--------------+--------+-------+--------');
        final ordered = [...replies]
          ..sort((a, b) => a.workerId.compareTo(b.workerId));
        for (final reply in ordered) {
          final payload = reply.payload;
          final statusLabel = (payload['status'] ?? reply.status).toString();
          final modeLabel = (payload['mode'] ?? mode).toString();
          final activeLabel = (payload['active'] ?? '-').toString();
          dependencies.out.writeln(
            '${reply.workerId.padRight(14)}| '
            '${statusLabel.padRight(6)} | '
            '${modeLabel.padRight(5)} | '
            '${activeLabel.padRight(6)}',
          );
        }
      }

      return replies.isEmpty ? 70 : 0;
    } finally {
      await ctx.dispose();
    }
  }
}

class WorkerStatusCommand extends Command<int> {
  WorkerStatusCommand(this.dependencies) {
    argParser
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
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'status';

  @override
  final String description = 'Show worker heartbeat status.';

  @override
  Future<int> run() async {
    late CliContext ctx;
    try {
      ctx = await dependencies.createCliContext();
    } catch (error, stack) {
      dependencies.err.writeln('Failed to initialize Stem context: $error');
      dependencies.err.writeln(stack);
      return 70;
    }

    try {
      return _workerStatus(
        argResults!,
        dependencies.out,
        dependencies.err,
        context: ctx,
        environment: dependencies.environment,
      );
    } finally {
      await ctx.dispose();
    }
  }

  Future<int> _workerStatus(
    ArgResults args,
    StringSink out,
    StringSink err, {
    CliContext? context,
    required Map<String, String> environment,
  }) async {
    final namespaceInput = (args['namespace'] as String?)?.trim();
    final filters = ((args['worker'] as List?) ?? const [])
        .cast<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final follow = args['follow'] as bool? ?? false;
    final jsonOutput = args['json'] as bool? ?? false;
    final heartbeatInterval = ObservabilityConfig.parseDuration(
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

    final env = environment;
    final brokerUrl = (args['broker'] as String?) ?? env[brokerEnvKey] ?? '';
    final backendUrl = (args['backend'] as String?) ?? env[backendEnvKey];
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
            'No heartbeat received within ${formatReadableDuration(timeout)} '
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
          if (filters.isNotEmpty && !filters.contains(heartbeat.workerId)) {
            return;
          }
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
      }).toList()
        ..sort((a, b) => a.workerId.compareTo(b.workerId));
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
      '${isStale ? ' [stale ${formatReadableDuration(age)}]' : ''}',
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
    final connection = redis.RedisConnection();
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

    final pubSub = redis.PubSub(command);
    return _PubSubHandle(connection, command, pubSub);
  }
}

class _BackendHandle {
  _BackendHandle({required this.backend, this.dispose});

  final ResultBackend backend;
  final Future<void> Function()? dispose;
}

class _PubSubHandle {
  _PubSubHandle(this.connection, this.command, this.pubSub);

  final redis.RedisConnection connection;
  final redis.Command command;
  final redis.PubSub pubSub;

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

Future<void> _publishControlCommand(
  CliContext ctx, {
  required ControlCommandMessage command,
  required String namespace,
  required Set<String> targets,
}) async {
  late final List<String> queueNames;
  if (targets.isEmpty) {
    queueNames = [ControlQueueNames.broadcast(namespace)];
  } else {
    queueNames = targets
        .map((target) => ControlQueueNames.worker(namespace, target))
        .toList()
      ..sort();
  }

  for (final queue in queueNames) {
    await ctx.broker.publish(command.toEnvelope(queue: queue));
  }
}

Future<List<ControlReplyMessage>> _collectControlReplies(
  CliContext ctx, {
  required String namespace,
  required String requestId,
  int? expectedWorkers,
  required Duration timeout,
}) async {
  final replyQueue = ControlQueueNames.reply(namespace, requestId);
  final replies = <ControlReplyMessage>[];
  final seenWorkers = <String>{};
  final completer = Completer<void>();

  late final StreamSubscription<Delivery> subscription;
  subscription = ctx.broker
      .consume(
    replyQueue,
    prefetch: 10,
    consumerName: 'stem-cli-control-$requestId',
  )
      .listen(
    (delivery) async {
      try {
        final reply = controlReplyFromEnvelope(delivery.envelope);
        replies.add(reply);
        seenWorkers.add(reply.workerId);
        await ctx.broker.ack(delivery);
        if (!completer.isCompleted &&
            expectedWorkers != null &&
            seenWorkers.length >= expectedWorkers) {
          completer.complete();
        }
      } catch (_) {
        await ctx.broker.ack(delivery);
      }
    },
    onError: (_, __) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    },
  );

  await Future.any([
    completer.future,
    Future.delayed(timeout),
  ]);
  await subscription.cancel();
  return replies;
}

class WorkerMultiCommand extends Command<int> {
  WorkerMultiCommand(this.dependencies) {
    argParser
      ..addMultiOption(
        'command',
        help:
            'Executable and arguments for each worker node (repeat the option to provide multiple tokens).',
        valueHelp: 'arg',
      )
      ..addOption(
        'command-line',
        help:
            'Full command string (with optional quoting) executed per node when starting workers.',
        valueHelp: 'cmd',
      )
      ..addOption(
        'pidfile',
        defaultsTo: '/var/run/stem/%n.pid',
        valueHelp: 'path',
        help:
            'PID file template. Supports %n (node), %h (hostname), %I (index), %d (UTC timestamp).',
      )
      ..addOption(
        'logfile',
        defaultsTo: '/var/log/stem/%n.log',
        valueHelp: 'path',
        help: 'Log file template. Supports the same placeholders as --pidfile.',
      )
      ..addOption(
        'workdir',
        defaultsTo: '.',
        valueHelp: 'path',
        help: 'Working directory for launched processes (templated).',
      )
      ..addOption(
        'env-file',
        valueHelp: 'path',
        help:
            'Load KEY=VALUE pairs from file before launching worker processes.',
      )
      ..addFlag(
        'detach',
        defaultsTo: true,
        help:
            'Run processes in the background (use --no-detach or --foreground to stay attached).',
      )
      ..addFlag(
        'foreground',
        defaultsTo: false,
        negatable: false,
        help:
            'Alias for --no-detach. Runs a single node in the foreground and inherits stdio.',
      )
      ..addOption(
        'timeout',
        defaultsTo: '30s',
        valueHelp: 'duration',
        help:
            'Grace period before forcing termination when stopping or restarting nodes.',
      );
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'multi';

  @override
  final String description =
      'Manage multiple worker processes (start, stop, restart, status).';

  @override
  Future<int> run() async {
    final args = argResults!;
    final rest = List<String>.from(args.rest);
    if (rest.isEmpty) {
      dependencies.err.writeln(
          'Usage: stem worker multi <start|stop|restart|status> <nodes...>');
      return 64;
    }

    final action = rest.first;
    final requestedNodes = rest.skip(1).toList();
    final nodes = _multiResolveNodes(requestedNodes, dependencies.environment);

    switch (action) {
      case 'start':
        if (nodes.isEmpty) {
          dependencies.err.writeln('No worker nodes specified for start.');
          return 64;
        }
        return _start(nodes, args);
      case 'stop':
        if (nodes.isEmpty) {
          dependencies.err.writeln('No worker nodes specified for stop.');
          return 64;
        }
        return _stop(nodes, args);
      case 'restart':
        if (nodes.isEmpty) {
          dependencies.err.writeln('No worker nodes specified for restart.');
          return 64;
        }
        return _restart(nodes, args);
      case 'status':
        if (nodes.isEmpty) {
          dependencies.err.writeln('No worker nodes specified for status.');
          return 64;
        }
        return _status(nodes, args);
      default:
        dependencies.err.writeln(
            'Unknown action "$action". Use start, stop, restart, or status.');
        return 64;
    }
  }

  Future<int> _start(List<String> nodes, ArgResults args) async {
    final envFilePath = args['env-file'] as String?;
    final baseEnv =
        _buildBaseEnvironment(dependencies.environment, envFilePath);
    if (baseEnv == null) {
      return 70;
    }

    final commandArgs = _resolveCommandArgs(args, baseEnv);
    if (commandArgs == null || commandArgs.isEmpty) {
      dependencies.err.writeln(
        'No worker command configured. Provide --command / --command-line or set STEM_WORKER_COMMAND.',
      );
      return 64;
    }

    final pidTemplate = args['pidfile'] as String? ?? '/var/run/stem/%n.pid';
    final logTemplate = args['logfile'] as String? ?? '/var/log/stem/%n.log';
    final workdirTemplate = args['workdir'] as String? ?? '.';
    final timeout = parseOptionalDuration(args['timeout'] as String?) ??
        const Duration(seconds: 30);

    final detachFlag = (args['detach'] as bool? ?? true) &&
        !(args['foreground'] as bool? ?? false);
    if (!detachFlag && nodes.length > 1) {
      dependencies.err.writeln(
          'Foreground mode supports only one node. Specify a single node.');
      return 64;
    }

    final startOptions = _StartOptions(
      pidTemplate: pidTemplate,
      logTemplate: logTemplate,
      workdirTemplate: workdirTemplate,
      commandArgs: commandArgs,
      detach: detachFlag,
      timeout: timeout,
      environment: baseEnv,
    );

    final timestamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final host = _hostname;

    var exitCode = 0;
    for (var i = 0; i < nodes.length; i++) {
      final context = _NodeContext(
        name: nodes[i],
        index: i + 1,
        host: host,
        timestamp: timestamp,
      );
      final code = await _startNode(
          context, startOptions, dependencies.out, dependencies.err);
      if (code != 0) {
        exitCode = code;
        if (!startOptions.detach) {
          return code;
        }
      }
    }
    return exitCode;
  }

  Future<int> _stop(List<String> nodes, ArgResults args) async {
    final pidTemplate = args['pidfile'] as String? ?? '/var/run/stem/%n.pid';
    final timeout = parseOptionalDuration(args['timeout'] as String?) ??
        const Duration(seconds: 30);
    final stopOptions = _StopOptions(
      pidTemplate: pidTemplate,
      timeout: timeout,
    );

    final host = _hostname;
    final timestamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');

    var exitCode = 0;
    for (var i = 0; i < nodes.length; i++) {
      final context = _NodeContext(
        name: nodes[i],
        index: i + 1,
        host: host,
        timestamp: timestamp,
      );
      final code = await _stopNode(
          context, stopOptions, dependencies.out, dependencies.err);
      if (code != 0) {
        exitCode = code;
      }
    }
    return exitCode;
  }

  Future<int> _restart(List<String> nodes, ArgResults args) async {
    final stopCode = await _stop(nodes, args);
    if (stopCode != 0) {
      return stopCode;
    }
    return _start(nodes, args);
  }

  Future<int> _status(List<String> nodes, ArgResults args) async {
    final pidTemplate = args['pidfile'] as String? ?? '/var/run/stem/%n.pid';
    final statusOptions = _StopOptions(
      pidTemplate: pidTemplate,
      timeout: Duration.zero,
    );

    final host = _hostname;
    final timestamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');

    var exitCode = 0;
    for (var i = 0; i < nodes.length; i++) {
      final context = _NodeContext(
        name: nodes[i],
        index: i + 1,
        host: host,
        timestamp: timestamp,
      );
      final code = await _statusNode(context, statusOptions, dependencies.out);
      if (code != 0) {
        exitCode = code;
      }
    }
    return exitCode;
  }

  Map<String, String>? _buildBaseEnvironment(
    Map<String, String> base,
    String? envFilePath,
  ) {
    final merged = <String, String>{...base};
    if (envFilePath == null) {
      return merged;
    }
    try {
      final envFromFile = _loadEnvironmentFile(envFilePath);
      merged.addAll(envFromFile);
      return merged;
    } on Object catch (error) {
      dependencies.err
          .writeln('Failed to load environment file "$envFilePath": $error');
      return null;
    }
  }

  List<String>? _resolveCommandArgs(ArgResults args, Map<String, String> env) {
    final listArgs =
        (args['command'] as List?)?.cast<String>() ?? const <String>[];
    if (listArgs.isNotEmpty) {
      return List<String>.from(listArgs);
    }
    final commandLine = (args['command-line'] as String?)?.trim();
    if (commandLine != null && commandLine.isNotEmpty) {
      return _multiSplitCommandLine(commandLine);
    }
    final envCommand = env['STEM_WORKER_COMMAND'] ?? env['STEMD_COMMAND'];
    if (envCommand != null && envCommand.trim().isNotEmpty) {
      return _multiSplitCommandLine(envCommand);
    }
    return null;
  }
}

class WorkerHealthcheckCommand extends Command<int> {
  WorkerHealthcheckCommand(this.dependencies) {
    argParser
      ..addOption(
        'pidfile',
        valueHelp: 'path',
        help: 'PID file for the worker process.',
      )
      ..addOption(
        'node',
        help: 'Worker node name (defaults to pidfile basename).',
      )
      ..addOption(
        'logfile',
        valueHelp: 'path',
        help: 'Optional log file for context.',
      )
      ..addFlag(
        'json',
        defaultsTo: false,
        negatable: false,
        help: 'Emit health information as JSON.',
      )
      ..addFlag(
        'quiet',
        defaultsTo: false,
        negatable: false,
        help: 'Suppress healthy output when not using --json.',
      );
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'healthcheck';

  @override
  final String description =
      'Probe worker process health for use in readiness/liveness checks.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final pidfileArg = (args['pidfile'] as String?)?.trim();
    if (pidfileArg == null || pidfileArg.isEmpty) {
      dependencies.err.writeln('Missing required --pidfile <path>.');
      return 64;
    }
    final pidfile = p.normalize(pidfileArg);
    final node = _inferNodeName((args['node'] as String?)?.trim(), pidfile);
    final logPath = (args['logfile'] as String?)?.trim();
    final jsonOutput = args['json'] as bool? ?? false;
    final quiet = args['quiet'] as bool? ?? false;

    final pid = _readPidFile(pidfile);
    bool running = false;
    String? error;
    if (pid == null) {
      error = File(pidfile).existsSync() ? 'invalid-pid' : 'pidfile-missing';
    } else {
      running = await _isPidRunning(pid);
      if (!running) {
        error = 'process-not-running';
      }
    }

    final since = _pidFileTimestamp(pidfile);
    final uptime =
        since != null ? DateTime.now().toUtc().difference(since) : null;

    final payload = <String, Object?>{
      'status': running ? 'ok' : 'error',
      'node': node,
      'pidfile': pidfile,
      if (logPath != null && logPath.isNotEmpty) 'logfile': logPath,
      if (pid != null) 'pid': pid,
      if (since != null) 'since': since.toIso8601String(),
      if (uptime != null) 'uptimeSeconds': uptime.inSeconds,
      if (!running && error != null) 'error': error,
    };

    if (jsonOutput) {
      dependencies.out.writeln(jsonEncode(payload));
    } else if (!quiet || !running) {
      if (running) {
        final uptimeText =
            uptime != null ? formatReadableDuration(uptime) : 'unknown';
        dependencies.out.writeln(
          'Worker ${node ?? '(unknown)'} healthy (pid ${pid ?? '-'}, uptime $uptimeText).',
        );
      } else {
        final reason = error ?? 'unhealthy';
        dependencies.out.writeln(
          'Worker ${node ?? '(unknown)'} unhealthy: $reason (pidfile $pidfile).',
        );
      }
    }

    return running ? 0 : 70;
  }
}

class WorkerDiagnoseCommand extends Command<int> {
  WorkerDiagnoseCommand(this.dependencies) {
    argParser
      ..addOption(
        'pidfile',
        valueHelp: 'path',
        help: 'PID file to validate.',
      )
      ..addOption(
        'logfile',
        valueHelp: 'path',
        help: 'Log file expected for the worker.',
      )
      ..addOption(
        'env-file',
        valueHelp: 'path',
        help: 'Environment file to validate (optional).',
      )
      ..addFlag(
        'json',
        defaultsTo: false,
        negatable: false,
        help: 'Emit results as JSON.',
      );
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'diagnose';

  @override
  final String description =
      'Run common daemonization checks (directories, pidfiles, environment).';

  @override
  Future<int> run() async {
    final args = argResults!;
    final jsonOutput = args['json'] as bool? ?? false;
    final entries = <_DiagnosticEntry>[];

    void addEntry(String check, bool ok,
        {String level = 'info', String? message}) {
      entries.add(_DiagnosticEntry(
        check: check,
        ok: ok,
        level: level,
        message: message,
      ));
    }

    final pidfileArg = (args['pidfile'] as String?)?.trim();
    if (pidfileArg == null || pidfileArg.isEmpty) {
      addEntry('pidfile option provided', false,
          level: 'warning', message: 'No --pidfile supplied.');
    } else {
      final pidfile = p.normalize(pidfileArg);
      final pidDir = Directory(p.dirname(pidfile));
      if (pidDir.existsSync()) {
        addEntry('PID directory exists', true, message: pidDir.path);
      } else {
        addEntry('PID directory exists', false,
            level: 'error', message: '${pidDir.path} is missing');
      }

      final pidFile = File(pidfile);
      if (pidFile.existsSync()) {
        addEntry('PID file present', true, message: pidfile);
        final pid = _readPidFile(pidfile);
        if (pid == null) {
          addEntry('PID file parses correctly', false,
              level: 'error', message: 'Unable to parse integer PID.');
        } else {
          final running = await _isPidRunning(pid);
          if (running) {
            addEntry(
              'Worker process running',
              true,
              message: 'pid $pid (${_describeUptime(pidfile)})',
            );
          } else {
            addEntry(
              'Worker process running',
              false,
              level: 'error',
              message: 'Process $pid not running (stale pid file).',
            );
          }
        }
      } else {
        addEntry('PID file present', false,
            level: 'warning', message: '$pidfile missing');
      }
    }

    final logfileArg = (args['logfile'] as String?)?.trim();
    if (logfileArg != null && logfileArg.isNotEmpty) {
      final logfile = p.normalize(logfileArg);
      final logDir = Directory(p.dirname(logfile));
      if (logDir.existsSync()) {
        addEntry('Log directory exists', true, message: logDir.path);
      } else {
        addEntry('Log directory exists', false,
            level: 'error', message: '${logDir.path} is missing');
      }

      final logFile = File(logfile);
      if (logFile.existsSync()) {
        addEntry('Log file present', true, message: logfile);
      } else {
        addEntry('Log file present', false,
            level: 'warning',
            message: '$logfile not found (will be created on first write).');
      }
    }

    final envFileArg = (args['env-file'] as String?)?.trim();
    if (envFileArg != null && envFileArg.isNotEmpty) {
      final envPath = p.normalize(envFileArg);
      try {
        final env = _loadEnvironmentFile(envPath);
        addEntry('Environment file parsed', true, message: envPath);
        if (env['STEM_WORKER_COMMAND'] != null &&
            (env['STEM_WORKER_COMMAND'] as String).trim().isNotEmpty) {
          addEntry('STEM_WORKER_COMMAND defined', true,
              message: env['STEM_WORKER_COMMAND'] as String);
        } else {
          addEntry('STEM_WORKER_COMMAND defined', false,
              level: 'warning', message: 'Key not found in environment file.');
        }
      } catch (error) {
        addEntry('Environment file parsed', false,
            level: 'error', message: error.toString());
      }
    }

    final hasError =
        entries.any((entry) => !entry.ok && entry.level == 'error');

    if (jsonOutput) {
      final payload = {
        'status': hasError ? 'error' : 'ok',
        'checks': entries
            .map(
              (entry) => {
                'check': entry.check,
                'ok': entry.ok,
                'level': entry.level,
                if (entry.message != null) 'message': entry.message,
              },
            )
            .toList(growable: false),
      };
      dependencies.out.writeln(jsonEncode(payload));
    } else {
      for (final entry in entries) {
        final prefix = entry.ok
            ? '[OK ]'
            : entry.level == 'warning'
                ? '[WARN]'
                : '[ERR]';
        final detail = entry.message != null ? ' - ${entry.message}' : '';
        dependencies.out.writeln('$prefix ${entry.check}$detail');
      }
      dependencies.out.writeln(
        hasError
            ? 'Diagnostics detected errors. See guidance in the daemonization docs.'
            : 'All diagnostics passed.',
      );
    }

    return hasError ? 70 : 0;
  }
}

class _NodeContext {
  _NodeContext({
    required this.name,
    required this.index,
    required this.host,
    required this.timestamp,
  });

  final String name;
  final int index;
  final String host;
  final String timestamp;
}

class _StartOptions {
  const _StartOptions({
    required this.pidTemplate,
    required this.logTemplate,
    required this.workdirTemplate,
    required this.commandArgs,
    required this.detach,
    required this.timeout,
    required this.environment,
  });

  final String pidTemplate;
  final String logTemplate;
  final String workdirTemplate;
  final List<String> commandArgs;
  final bool detach;
  final Duration timeout;
  final Map<String, String> environment;
}

class _StopOptions {
  const _StopOptions({
    required this.pidTemplate,
    required this.timeout,
  });

  final String pidTemplate;
  final Duration timeout;
}

final String _hostname = Platform.localHostname;

class _DiagnosticEntry {
  const _DiagnosticEntry({
    required this.check,
    required this.ok,
    required this.level,
    this.message,
  });

  final String check;
  final bool ok;
  final String level;
  final String? message;
}

String? _inferNodeName(String? provided, String pidfile) {
  if (provided != null && provided.isNotEmpty) {
    return provided;
  }
  final base = p.basename(pidfile);
  final dotIndex = base.indexOf('.');
  return dotIndex > 0 ? base.substring(0, dotIndex) : base;
}

DateTime? _pidFileTimestamp(String pidfile) {
  final file = File(pidfile);
  if (!file.existsSync()) {
    return null;
  }
  try {
    final stat = file.statSync();
    return stat.changed.toUtc();
  } catch (_) {
    return null;
  }
}

String _describeUptime(String pidfile) {
  final since = _pidFileTimestamp(pidfile);
  if (since == null) {
    return 'uptime unknown';
  }
  final duration = DateTime.now().toUtc().difference(since);
  return 'uptime ${formatReadableDuration(duration)}';
}

Future<int> _startNode(
  _NodeContext context,
  _StartOptions options,
  StringSink out,
  StringSink err,
) async {
  final pidPath = _resolvePath(options.pidTemplate, context);
  final logPath = _resolvePath(options.logTemplate, context);
  final workDir = _resolvePath(options.workdirTemplate, context);

  final existingPid = _readPidFile(pidPath);
  if (existingPid != null) {
    if (await _isPidRunning(existingPid)) {
      err.writeln(
        'Node ${context.name} appears to be running already (pid $existingPid).',
      );
      return 1;
    }
    _removePidFile(pidPath);
  }

  _ensureParentDirectory(pidPath);
  _ensureParentDirectory(logPath);
  File(logPath).createSync(recursive: true);
  Directory(workDir).createSync(recursive: true);

  final expandedCommand = _expandTemplates(options.commandArgs, context);
  if (expandedCommand.isEmpty) {
    err.writeln('Resolved command for ${context.name} is empty.');
    return 64;
  }

  final executable = expandedCommand.first;
  final executableArgs = expandedCommand.length > 1
      ? expandedCommand.sublist(1)
      : const <String>[];

  final env = <String, String>{...options.environment};
  env['STEM_WORKER_NODE'] = context.name;
  env['STEM_WORKER_INDEX'] = context.index.toString();
  env['STEM_WORKER_PIDFILE'] = pidPath;
  env['STEM_WORKER_LOGFILE'] = logPath;
  env['STEM_WORKER_HOST'] = context.host;

  try {
    final process = await Process.start(
      executable,
      executableArgs,
      workingDirectory: workDir,
      environment: env,
      mode: options.detach
          ? ProcessStartMode.detachedWithStdio
          : ProcessStartMode.inheritStdio,
    );

    _writePidFile(pidPath, process.pid);

    if (options.detach) {
      out.writeln('Started ${context.name} (pid ${process.pid}).');
      return 0;
    }

    out.writeln(
        'Started ${context.name} (pid ${process.pid}); waiting for exit...');
    final exitCode = await process.exitCode;
    _removePidFile(pidPath);
    if (exitCode != 0) {
      err.writeln('Process ${context.name} exited with code $exitCode.');
    }
    return exitCode;
  } on ProcessException catch (error) {
    err.writeln('Failed to launch ${context.name}: $error');
    return 70;
  }
}

Future<int> _stopNode(
  _NodeContext context,
  _StopOptions options,
  StringSink out,
  StringSink err,
) async {
  final pidPath = _resolvePath(options.pidTemplate, context);
  final pid = _readPidFile(pidPath);
  if (pid == null) {
    out.writeln('${context.name}: no PID file found at $pidPath.');
    return 0;
  }

  out.writeln('Stopping ${context.name} (pid $pid)...');
  final terminated = await _sendSigterm(pid);
  if (!terminated) {
    err.writeln('Failed to send termination signal to pid $pid.');
  }

  final exited = await _waitForExit(pid, options.timeout);
  if (!exited) {
    err.writeln(
      'Process ${context.name} did not exit within ${options.timeout.inSeconds}s; sending SIGKILL.',
    );
    await _sendSigkill(pid);
    final forcedExit = await _waitForExit(pid, const Duration(seconds: 5));
    if (!forcedExit) {
      err.writeln('Unable to terminate ${context.name} (pid $pid).');
      return 70;
    }
  }

  _removePidFile(pidPath);
  out.writeln('Stopped ${context.name}.');
  return 0;
}

Future<int> _statusNode(
  _NodeContext context,
  _StopOptions options,
  StringSink out,
) async {
  final pidPath = _resolvePath(options.pidTemplate, context);
  final pid = _readPidFile(pidPath);
  if (pid == null) {
    out.writeln('${context.name}: not running (no PID file).');
    return 3;
  }

  final running = await _isPidRunning(pid);
  if (running) {
    out.writeln('${context.name}: running (pid $pid).');
    return 0;
  }

  out.writeln('${context.name}: not running (stale pid $pid).');
  _removePidFile(pidPath);
  return 3;
}

List<String> _multiResolveNodes(
  List<String> requested,
  Map<String, String> environment,
) {
  if (requested.isNotEmpty) {
    return requested;
  }
  final envNodes =
      environment['STEMD_NODES'] ?? environment['STEM_WORKER_NODES'];
  if (envNodes == null || envNodes.trim().isEmpty) {
    return const [];
  }
  return envNodes
      .split(RegExp(r'\s+'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();
}

List<String> _expandTemplates(
  List<String> templates,
  _NodeContext context,
) {
  return templates
      .map((template) => _expandTemplate(template, context))
      .toList(growable: false);
}

String _expandTemplate(String template, _NodeContext context) {
  return template.replaceAllMapped(RegExp(r'%[nNhIiDd]'), (match) {
    switch (match.group(0)) {
      case '%n':
        return context.name;
      case '%N':
        return context.name.toUpperCase();
      case '%h':
        return context.host;
      case '%I':
      case '%i':
        return context.index.toString();
      case '%d':
        return context.timestamp;
      default:
        return match.group(0)!;
    }
  });
}

String _resolvePath(String template, _NodeContext context) {
  final expanded = _expandTemplate(template, context);
  if (expanded.isEmpty) {
    return expanded;
  }
  return p.isAbsolute(expanded)
      ? p.normalize(expanded)
      : p.normalize(p.join(Directory.current.path, expanded));
}

int? _readPidFile(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    return null;
  }
  try {
    final contents = file.readAsStringSync().trim();
    if (contents.isEmpty) {
      return null;
    }
    final pid = int.parse(contents, radix: 10);
    return pid;
  } catch (_) {
    return null;
  }
}

void _writePidFile(String path, int pid) {
  File(path).writeAsStringSync('$pid\n', flush: true);
}

void _removePidFile(String path) {
  final file = File(path);
  if (file.existsSync()) {
    try {
      file.deleteSync();
    } catch (_) {}
  }
}

void _ensureParentDirectory(String path) {
  final parent = Directory(p.dirname(path));
  if (!parent.existsSync()) {
    parent.createSync(recursive: true);
  }
}

Future<bool> _isPidRunning(int pid) async {
  if (Platform.isWindows) {
    final result = await Process.run(
      'tasklist',
      ['/FI', 'PID eq $pid'],
      runInShell: true,
    );
    if (result.exitCode != 0) {
      return false;
    }
    final output = result.stdout.toString().toLowerCase();
    return output.contains(' $pid ') ||
        output.contains(' $pid\r') ||
        output.contains(' pid eq $pid');
  }
  final result = await Process.run('kill', ['-0', '$pid']);
  return result.exitCode == 0;
}

Future<bool> _waitForExit(int pid, Duration timeout) async {
  if (timeout.isNegative) {
    return false;
  }
  final deadline = DateTime.now().add(timeout);
  while (await _isPidRunning(pid)) {
    if (DateTime.now().isAfter(deadline)) {
      return false;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  return true;
}

Future<bool> _sendSigterm(int pid) async {
  if (Platform.isWindows) {
    return Process.killPid(pid);
  }
  final result = await Process.run('kill', ['-TERM', '$pid']);
  return result.exitCode == 0;
}

Future<bool> _sendSigkill(int pid) async {
  if (Platform.isWindows) {
    return Process.killPid(pid);
  }
  final result = await Process.run('kill', ['-KILL', '$pid']);
  return result.exitCode == 0;
}

Map<String, String> _loadEnvironmentFile(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError('Environment file not found: $path');
  }
  final result = <String, String>{};
  for (final rawLine in file.readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    final sanitized =
        line.startsWith('export ') ? line.substring(7).trim() : line;
    final splitIndex = sanitized.indexOf('=');
    if (splitIndex <= 0) {
      continue;
    }
    final key = sanitized.substring(0, splitIndex).trim();
    var value = sanitized.substring(splitIndex + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith('\'') && value.endsWith('\''))) {
      value = value.substring(1, value.length - 1);
    }
    value = value.replaceAll(r'\n', '\n');
    result[key] = value;
  }
  return result;
}

List<String> _multiSplitCommandLine(String commandLine) {
  final result = <String>[];
  final buffer = StringBuffer();
  var inSingle = false;
  var inDouble = false;

  for (var i = 0; i < commandLine.length; i++) {
    final char = commandLine[i];
    if (char == '\'' && !inDouble) {
      inSingle = !inSingle;
      continue;
    }
    if (char == '"' && !inSingle) {
      inDouble = !inDouble;
      continue;
    }
    if (char == '\\' && !inSingle && i + 1 < commandLine.length) {
      buffer.write(commandLine[i + 1]);
      i += 1;
      continue;
    }
    if (char.trim().isEmpty && !inSingle && !inDouble) {
      if (buffer.isNotEmpty) {
        result.add(buffer.toString());
        buffer.clear();
      }
      continue;
    }
    buffer.write(char);
  }
  if (buffer.isNotEmpty) {
    result.add(buffer.toString());
  }
  return result;
}
