import 'dart:convert';

import 'package:artisanal/args.dart';
import 'package:stem/stem.dart';

import 'dependencies.dart';
import 'utilities.dart';
import 'workflow_context.dart';

class WorkflowCommand extends Command<int> {
  WorkflowCommand(this.dependencies) {
    addSubcommand(_WorkflowStartCommand(dependencies));
    addSubcommand(_WorkflowListCommand(dependencies));
    addSubcommand(_WorkflowShowCommand(dependencies));
    addSubcommand(_WorkflowCancelCommand(dependencies));
    addSubcommand(_WorkflowRewindCommand(dependencies));
    addSubcommand(_WorkflowEmitCommand(dependencies));
    addSubcommand(_WorkflowWaitersCommand(dependencies));
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'wf';

  @override
  final String description = 'Manage durable workflow runs.';

  @override
  Future<int> run() async {
    throw Exception('Specify a workflow subcommand.');
  }
}

class _WorkflowStartCommand extends Command<int> {
  _WorkflowStartCommand(this.dependencies) {
    argParser
      ..addOption(
        'params',
        abbr: 'p',
        help: 'JSON payload for workflow parameters.',
        valueHelp: '{"key":"value"}',
      )
      ..addOption('parent', help: 'Optional parent workflow run identifier.')
      ..addOption(
        'ttl',
        help: 'Optional TTL (e.g. 10m, 2h) for the workflow record.',
      )
      ..addOption(
        'max-run',
        help: 'Auto-cancel the run after this duration (e.g. 15m, 2h).',
      )
      ..addOption(
        'max-suspend',
        help:
            'Auto-cancel when a suspension exceeds this duration (e.g. 30s, 5m).',
      );
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'start';

  @override
  final String description = 'Start a workflow run.';

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.isEmpty) {
      dependencies.err.writeln('Missing workflow name.');
      return 64;
    }
    final workflowName = args.rest.first;
    final paramsRaw = args['params'] as String?;
    Map<String, Object?> params = const {};
    if (paramsRaw != null && paramsRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(paramsRaw);
        if (decoded is Map) {
          params = decoded.cast<String, Object?>();
        } else {
          dependencies.err.writeln('--params must decode to a JSON object.');
          return 64;
        }
      } on FormatException catch (error) {
        dependencies.err.writeln('Invalid JSON for --params: $error');
        return 64;
      }
    }
    final parent = (args['parent'] as String?)?.trim();
    final ttlValue = parseOptionalDuration(args['ttl'] as String?);
    Duration? maxRun;
    final maxRunRaw = args['max-run'] as String?;
    if (maxRunRaw != null && maxRunRaw.trim().isNotEmpty) {
      maxRun = parseOptionalDuration(maxRunRaw);
      if (maxRun == null) {
        dependencies.err.writeln(
          'Invalid --max-run value. Expected formats like 30s, 5m, 2h.',
        );
        return 64;
      }
    }
    Duration? maxSuspend;
    final maxSuspendRaw = args['max-suspend'] as String?;
    if (maxSuspendRaw != null && maxSuspendRaw.trim().isNotEmpty) {
      maxSuspend = parseOptionalDuration(maxSuspendRaw);
      if (maxSuspend == null) {
        dependencies.err.writeln(
          'Invalid --max-suspend value. Expected formats like 30s, 5m, 2h.',
        );
        return 64;
      }
    }
    WorkflowCancellationPolicy? cancellationPolicy;
    if (maxRun != null || maxSuspend != null) {
      cancellationPolicy = WorkflowCancellationPolicy(
        maxRunDuration: maxRun,
        maxSuspendDuration: maxSuspend,
      );
    }
    WorkflowCliContext? workflowContext;
    try {
      workflowContext = await dependencies.createWorkflowContext();
      final runtime = workflowContext.runtime;
      if (runtime.registry.lookup(workflowName) == null) {
        dependencies.err.writeln(
          'Workflow "$workflowName" is not registered in this context.',
        );
        dependencies.err.writeln(
          'Provide a workflowContextBuilder that registers definitions.',
        );
        return 64;
      }
      final runId = await runtime.startWorkflow(
        workflowName,
        params: params,
        parentRunId: parent?.isEmpty ?? true ? null : parent,
        ttl: ttlValue,
        cancellationPolicy: cancellationPolicy,
      );
      dependencies.out.writeln('Started workflow: $runId');
      return 0;
    } catch (error, stackTrace) {
      dependencies.err
        ..writeln('Failed to start workflow: $error')
        ..writeln(stackTrace);
      return 70;
    } finally {
      if (workflowContext != null) {
        await workflowContext.dispose();
      }
    }
  }
}

class _WorkflowListCommand extends Command<int> {
  _WorkflowListCommand(this.dependencies) {
    argParser
      ..addOption('workflow', help: 'Filter by workflow name.')
      ..addOption(
        'status',
        help:
            'Filter by status (running|suspended|completed|failed|cancelled).',
      )
      ..addOption('limit', defaultsTo: '20', help: 'Number of runs to display.')
      ..addFlag(
        'json',
        negatable: false,
        defaultsTo: false,
        help: 'Emit output in JSON format.',
      );
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'ls';

  @override
  final String description = 'List workflow runs.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final limit = parseOptionalInt(
      args['limit'] as String?,
      'limit',
      dependencies.err,
      min: 1,
    );
    if (limit == null) {
      return 64;
    }
    final statusRaw = (args['status'] as String?)?.trim();
    WorkflowStatus? status;
    if (statusRaw != null && statusRaw.isNotEmpty) {
      try {
        status = WorkflowStatus.values.firstWhere(
          (value) => value.name == statusRaw,
        );
      } catch (_) {
        dependencies.err.writeln('Unknown status "$statusRaw".');
        return 64;
      }
    }
    final jsonOutput = args['json'] as bool? ?? false;
    final workflowFilter = (args['workflow'] as String?)?.trim();
    WorkflowCliContext? workflowContext;
    try {
      workflowContext = await dependencies.createWorkflowContext();
      final runs = await workflowContext.store.listRuns(
        workflow: workflowFilter != null && workflowFilter.isNotEmpty
            ? workflowFilter
            : null,
        status: status,
        limit: limit,
      );
      if (jsonOutput) {
        final payload = runs
            .map(
              (run) => {
                'id': run.id,
                'workflow': run.workflow,
                'status': run.status.name,
                'cursor': run.cursor,
                'waitTopic': run.waitTopic,
                'resumeAt': run.resumeAt?.toIso8601String(),
                'result': run.result,
                'lastError': run.lastError,
                'createdAt': run.createdAt.toIso8601String(),
                'updatedAt': run.updatedAt?.toIso8601String(),
                'cancellationPolicy': run.cancellationPolicy?.toJson(),
                'cancellationData': run.cancellationData,
              },
            )
            .toList();
        dependencies.out.writeln(jsonEncode(payload));
      } else if (runs.isEmpty) {
        dependencies.out.writeln('No workflow runs found.');
      } else {
        _renderRunsTable(runs);
      }
      return 0;
    } catch (error, stackTrace) {
      dependencies.err
        ..writeln('Failed to list workflows: $error')
        ..writeln(stackTrace);
      return 70;
    } finally {
      if (workflowContext != null) {
        await workflowContext.dispose();
      }
    }
  }

  void _renderRunsTable(List<RunState> runs) {
    final out = dependencies.out;
    out.writeln(
      '${padCell('ID', 26)}  '
      '${padCell('WORKFLOW', 20)}  '
      '${padCell('STATUS', 10)}  '
      '${padCell('CURSOR', 6)}  '
      '${padCell('WAITING', 20)}  '
      '${padCell('RESUME_AT', 26)}  '
      '${padCell('CANCEL_REASON', 20)}',
    );
    out.writeln('-' * 138);
    for (final run in runs) {
      final reason = run.cancellationData?['reason'] as String?;
      out.writeln(
        '${padCell(run.id, 26)}  '
        '${padCell(run.workflow, 20)}  '
        '${padCell(run.status.name, 10)}  '
        '${padCell(run.cursor.toString(), 6, alignRight: true)}  '
        '${padCell(run.waitTopic ?? '-', 20)}  '
        '${padCell(run.resumeAt?.toIso8601String() ?? '-', 26)}  '
        '${padCell(reason ?? '-', 20)}',
      );
    }
  }
}

class _WorkflowWaitersCommand extends Command<int> {
  _WorkflowWaitersCommand(this.dependencies) {
    argParser
      ..addOption('topic', help: 'Filter by suspension topic.')
      ..addOption('limit', defaultsTo: '20', help: 'Number of runs to display.')
      ..addFlag(
        'json',
        negatable: false,
        defaultsTo: false,
        help: 'Emit output in JSON format.',
      );
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'waiters';

  @override
  final String description =
      'List workflow runs currently suspended (optionally by topic).';

  @override
  Future<int> run() async {
    final args = argResults!;
    final limit = parseOptionalInt(
      args['limit'] as String?,
      'limit',
      dependencies.err,
      min: 1,
    );
    if (limit == null) {
      return 64;
    }
    final topic = (args['topic'] as String?)?.trim();
    final jsonOutput = args['json'] as bool? ?? false;

    WorkflowCliContext? workflowContext;
    try {
      workflowContext = await dependencies.createWorkflowContext();
      final store = workflowContext.store;
      final List<RunState> runs;
      if (topic != null && topic.isNotEmpty) {
        final ids = await store.runsWaitingOn(topic, limit: limit);
        runs = <RunState>[];
        for (final id in ids) {
          final state = await store.get(id);
          if (state != null) runs.add(state);
        }
      } else {
        runs = await store.listRuns(
          status: WorkflowStatus.suspended,
          limit: limit,
        );
      }
      if (runs.isEmpty) {
        dependencies.out.writeln(
          topic != null && topic.isNotEmpty
              ? 'No workflow runs waiting on "$topic".'
              : 'No suspended workflow runs found.',
        );
        return 0;
      }
      if (jsonOutput) {
        final payload = runs.map(_encodeSuspendedRun).toList();
        dependencies.out.writeln(jsonEncode(payload));
      } else {
        _renderWaitersTable(runs);
      }
      return 0;
    } catch (error, stackTrace) {
      dependencies.err
        ..writeln('Failed to list waiting workflow runs: $error')
        ..writeln(stackTrace);
      return 70;
    } finally {
      if (workflowContext != null) {
        await workflowContext.dispose();
      }
    }
  }

  Map<String, Object?> _encodeSuspendedRun(RunState run) {
    final suspension = run.suspensionData ?? const <String, Object?>{};
    final suspendedAt =
        parseIsoTimestamp(suspension['suspendedAt'] as String?) ??
        run.updatedAt ??
        run.createdAt;
    final resumeAt =
        parseIsoTimestamp(
          suspension['resumeAt'] as String? ??
              suspension['deadline'] as String? ??
              suspension['policyDeadline'] as String?,
        ) ??
        run.resumeAt;
    return {
      'id': run.id,
      'workflow': run.workflow,
      'status': run.status.name,
      'step': suspension['step'],
      'topic': suspension['topic'] ?? run.waitTopic,
      'suspendedAt': suspendedAt.toIso8601String(),
      'resumeAt': resumeAt?.toIso8601String(),
      'suspensionData': suspension,
      'cancellationPolicy': run.cancellationPolicy?.toJson(),
      'cancellationData': run.cancellationData,
    };
  }

  void _renderWaitersTable(List<RunState> runs) {
    final out = dependencies.out;
    out.writeln(
      '${padCell('ID', 26)}  '
      '${padCell('WORKFLOW', 20)}  '
      '${padCell('STEP', 20)}  '
      '${padCell('TOPIC', 20)}  '
      '${padCell('SINCE', 26)}  '
      '${padCell('DEADLINE', 26)}  '
      '${padCell('POLICY', 20)}',
    );
    out.writeln('-' * 164);
    for (final run in runs) {
      final suspension = run.suspensionData ?? const <String, Object?>{};
      final step = suspension['step'] as String? ?? '-';
      final topic = suspension['topic'] as String? ?? run.waitTopic ?? '-';
      final suspendedAt =
          parseIsoTimestamp(suspension['suspendedAt'] as String?) ??
          run.updatedAt ??
          run.createdAt;
      final resumeAt =
          parseIsoTimestamp(
            suspension['resumeAt'] as String? ??
                suspension['deadline'] as String? ??
                suspension['policyDeadline'] as String?,
          ) ??
          run.resumeAt;
      final policySummary = _summarisePolicy(run.cancellationPolicy);
      out.writeln(
        '${padCell(run.id, 26)}  '
        '${padCell(run.workflow, 20)}  '
        '${padCell(step, 20)}  '
        '${padCell(topic, 20)}  '
        '${padCell(suspendedAt.toIso8601String(), 26)}  '
        '${padCell(resumeAt?.toIso8601String() ?? '-', 26)}  '
        '${padCell(policySummary, 20)}',
      );
    }
  }

  String _summarisePolicy(WorkflowCancellationPolicy? policy) {
    if (policy == null || policy.isEmpty) return '-';
    final parts = <String>[];
    final runLimit = policy.maxRunDuration;
    if (runLimit != null) {
      parts.add('run=${formatReadableDuration(runLimit)}');
    }
    final suspendLimit = policy.maxSuspendDuration;
    if (suspendLimit != null) {
      parts.add('suspend=${formatReadableDuration(suspendLimit)}');
    }
    return parts.isEmpty ? '-' : parts.join(', ');
  }
}

class _WorkflowShowCommand extends Command<int> {
  _WorkflowShowCommand(this.dependencies) {
    argParser
      ..addOption('id', help: 'Workflow run identifier.')
      ..addFlag(
        'json',
        negatable: false,
        defaultsTo: false,
        help: 'Emit detailed state as JSON.',
      );
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'show';

  @override
  final String description = 'Display workflow run details.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final runId =
        args['id'] as String? ??
        (args.rest.isNotEmpty ? args.rest.first : null);
    if (runId == null || runId.isEmpty) {
      dependencies.err.writeln('Missing workflow run identifier.');
      return 64;
    }
    final jsonOutput = args['json'] as bool? ?? false;
    WorkflowCliContext? workflowContext;
    try {
      workflowContext = await dependencies.createWorkflowContext();
      final state = await workflowContext.store.get(runId);
      if (state == null) {
        dependencies.err.writeln('Workflow run "$runId" not found.');
        return 64;
      }
      final steps = await workflowContext.store.listSteps(runId);
      if (jsonOutput) {
        dependencies.out.writeln(
          jsonEncode({
            'run': {
              'id': state.id,
              'workflow': state.workflow,
              'status': state.status.name,
              'cursor': state.cursor,
              'params': state.params,
              'result': state.result,
              'waitTopic': state.waitTopic,
              'resumeAt': state.resumeAt?.toIso8601String(),
              'lastError': state.lastError,
              'createdAt': state.createdAt.toIso8601String(),
              'updatedAt': state.updatedAt?.toIso8601String(),
              'cancellationPolicy': state.cancellationPolicy?.toJson(),
              'cancellationData': state.cancellationData,
            },
            'steps': steps
                .map(
                  (step) => {
                    'name': step.name,
                    'value': step.value,
                    'position': step.position,
                    'completedAt': step.completedAt?.toIso8601String(),
                  },
                )
                .toList(),
          }),
        );
      } else {
        _renderRunDetails(state, steps);
      }
      return 0;
    } catch (error, stackTrace) {
      dependencies.err
        ..writeln('Failed to show workflow run: $error')
        ..writeln(stackTrace);
      return 70;
    } finally {
      if (workflowContext != null) {
        await workflowContext.dispose();
      }
    }
  }

  void _renderRunDetails(RunState state, List<WorkflowStepEntry> steps) {
    final out = dependencies.out;
    out
      ..writeln('Run: ${state.id}')
      ..writeln('Workflow: ${state.workflow}')
      ..writeln('Status: ${state.status.name}')
      ..writeln('Cursor: ${state.cursor}')
      ..writeln('Wait Topic: ${state.waitTopic ?? '-'}')
      ..writeln('Resume At: ${state.resumeAt?.toIso8601String() ?? '-'}')
      ..writeln('Created At: ${state.createdAt.toIso8601String()}')
      ..writeln('Updated At: ${state.updatedAt?.toIso8601String() ?? '-'}')
      ..writeln('Params: ${jsonEncode(state.params)}')
      ..writeln('Result: ${jsonEncode(state.result)}');
    if (state.lastError != null && state.lastError!.isNotEmpty) {
      out.writeln('Last Error: ${jsonEncode(state.lastError)}');
    }
    if (state.cancellationPolicy != null &&
        !state.cancellationPolicy!.isEmpty) {
      out.writeln(
        'Cancellation Policy: ${jsonEncode(state.cancellationPolicy!.toJson())}',
      );
    }
    if (state.cancellationData != null && state.cancellationData!.isNotEmpty) {
      out.writeln('Cancellation Data: ${jsonEncode(state.cancellationData)}');
    }
    if (steps.isEmpty) {
      out.writeln('No checkpoints recorded.');
    } else {
      out.writeln('Checkpoints:');
      for (final step in steps) {
        out.writeln(
          '  [${step.position}] ${step.name}: ${jsonEncode(step.value)}',
        );
      }
    }
  }
}

class _WorkflowCancelCommand extends Command<int> {
  _WorkflowCancelCommand(this.dependencies);

  final StemCommandDependencies dependencies;

  @override
  final String name = 'cancel';

  @override
  final String description = 'Cancel a workflow run.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final runId = args.rest.isNotEmpty ? args.rest.first : null;
    if (runId == null || runId.isEmpty) {
      dependencies.err.writeln('Missing workflow run identifier.');
      return 64;
    }
    WorkflowCliContext? workflowContext;
    try {
      workflowContext = await dependencies.createWorkflowContext();
      await workflowContext.runtime.cancelWorkflow(runId);
      dependencies.out.writeln('Cancelled workflow run $runId.');
      return 0;
    } catch (error, stackTrace) {
      dependencies.err
        ..writeln('Failed to cancel workflow run: $error')
        ..writeln(stackTrace);
      return 70;
    } finally {
      if (workflowContext != null) {
        await workflowContext.dispose();
      }
    }
  }
}

class _WorkflowRewindCommand extends Command<int> {
  _WorkflowRewindCommand(this.dependencies) {
    argParser.addOption('step', help: 'Step name to rewind before.');
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'rewind';

  @override
  final String description = 'Rewind a workflow to a prior checkpoint.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final runId = args.rest.isNotEmpty ? args.rest.first : null;
    final stepName =
        args['step'] as String? ?? (args.rest.length > 1 ? args.rest[1] : null);
    if (runId == null ||
        runId.isEmpty ||
        stepName == null ||
        stepName.isEmpty) {
      dependencies.err.writeln(
        'Usage: stem wf rewind <runId> --step <stepName>',
      );
      return 64;
    }
    WorkflowCliContext? workflowContext;
    try {
      workflowContext = await dependencies.createWorkflowContext();
      await workflowContext.store.rewindToStep(runId, stepName);
      await workflowContext.store.markRunning(runId);
      dependencies.out.writeln('Rewound $runId to before step $stepName.');
      return 0;
    } catch (error, stackTrace) {
      dependencies.err
        ..writeln('Failed to rewind workflow run: $error')
        ..writeln(stackTrace);
      return 70;
    } finally {
      if (workflowContext != null) {
        await workflowContext.dispose();
      }
    }
  }
}

class _WorkflowEmitCommand extends Command<int> {
  _WorkflowEmitCommand(this.dependencies) {
    argParser.addOption(
      'payload',
      abbr: 'p',
      help: 'JSON payload delivered to waiting workflows.',
      valueHelp: '{"key":"value"}',
    );
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'emit';

  @override
  final String description = 'Emit an event to resume waiting workflows.';

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.isEmpty) {
      dependencies.err.writeln('Missing topic name.');
      return 64;
    }
    final topic = args.rest.first;
    final rawPayload = args['payload'] as String?;
    Map<String, Object?> payload = const {};
    if (rawPayload != null && rawPayload.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawPayload);
        if (decoded is Map) {
          payload = decoded.cast<String, Object?>();
        } else {
          dependencies.err.writeln('Event payload must be a JSON object.');
          return 64;
        }
      } on FormatException catch (error) {
        dependencies.err.writeln('Invalid JSON for --payload: $error');
        return 64;
      }
    }
    WorkflowCliContext? workflowContext;
    try {
      workflowContext = await dependencies.createWorkflowContext();
      await workflowContext.runtime.emit(topic, payload);
      dependencies.out.writeln('Emitted event "$topic" to waiting runs.');
      return 0;
    } catch (error, stackTrace) {
      dependencies.err
        ..writeln('Failed to emit workflow event: $error')
        ..writeln(stackTrace);
      return 70;
    } finally {
      if (workflowContext != null) {
        await workflowContext.dispose();
      }
    }
  }
}
