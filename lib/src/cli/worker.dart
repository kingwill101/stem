import 'dart:async';
import 'dart:convert';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:redis/redis.dart' as redis;
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
