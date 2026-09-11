// Sends a small, real in-memory Stem workload to a local OTLP/HTTP viewer.
//
// Run from packages/stem with:
//   dart run example/observability/local_traces.dart
//
// This example assumes the user's otel-desktop-viewer is listening on
// http://127.0.0.1:8000 and accepting OTLP/HTTP on 127.0.0.1:4318.
// ignore_for_file: avoid_print, avoid_redundant_argument_values, lines_longer_than_80_chars

import 'dart:io';

import 'package:contextual/contextual.dart' show Context, Level;
import 'package:stem/stem.dart';
import 'package:stem/src/observability/logging.dart' as implementation;

import 'telemetry_helpers.dart';

const _serviceName = 'stem-local-telemetry';
const _defaultOtlpEndpoint = 'http://localhost:4318';

final _localTask = FunctionTaskHandler<String>.inline(
  name: 'local-traces.normal-task',
  entrypoint: (context, args) async {
    final traceparent = context.headers['traceparent'];
    implementation.stemLogger.info(
      'Local task is executing with propagated context',
      Context({'task': 'local-traces.normal-task', 'phase': 'execute'}),
    );
    await context.progress(0.5, data: {'phase': 'execute'});
    final value = args['value'];
    await context.progress(1, data: {'phase': 'complete'});
    return 'normal-task:$value traceparent=$traceparent';
  },
);

final _retryTask = FunctionTaskHandler<String>.inline(
  name: 'local-traces.retry-once',
  options: const TaskOptions(maxRetries: 1),
  entrypoint: (context, args) async {
    if (context.attempt == 0) {
      implementation.stemLogger.warning(
        'Requesting the intentional local retry',
        Context({
          'task': 'local-traces.retry-once',
          'attempt': context.attempt,
        }),
      );
      throw TaskRetryRequest(countdown: const Duration(milliseconds: 100));
    }
    return 'retry-succeeded-attempt-${context.attempt}';
  },
);

final _failureTask = FunctionTaskHandler<String>.inline(
  name: 'local-traces.intentional-failure',
  options: const TaskOptions(maxRetries: 0),
  entrypoint: (context, args) async {
    throw StateError('Intentional local telemetry failure');
  },
);

final _fanoutTask = FunctionTaskHandler<String>.inline(
  name: 'local-traces.fanout-branch',
  entrypoint: (context, args) async => 'branch-${args['branch']}',
);

final _checkpointScript = WorkflowScript<String>(
  name: 'local-traces.checkpoint-script',
  checkpoints: [
    WorkflowCheckpoint(name: 'prepare'),
    WorkflowCheckpoint(name: 'complete'),
  ],
  run: (script) async {
    final prepared = await StemTracer.instance.trace<String>(
      'manual instrumentation: checkpoint.prepare',
      () => script.step<String>('prepare', (context) async {
        return 'prepared';
      }),
    );
    return StemTracer.instance.trace<String>(
      'manual instrumentation: checkpoint.complete',
      () => script.step<String>('complete', (context) async {
        return '$prepared-and-complete';
      }),
    );
  },
);

Future<void> main() async {
  if (Platform.environment['STEM_METRIC_EXPORTERS']?.trim().isNotEmpty ??
      false) {
    throw StateError(
      'Unset STEM_METRIC_EXPORTERS for this example: it explicitly owns one '
      'SDK for traces, metrics, and logs.',
    );
  }
  final otlpEndpoint =
      Platform.environment['OTEL_EXPORTER_OTLP_ENDPOINT'] ??
      _defaultOtlpEndpoint;
  final tracesExporter = Platform.environment['OTEL_TRACES_EXPORTER'];
  if (tracesExporter != null &&
      tracesExporter.trim().isNotEmpty &&
      tracesExporter.trim().toLowerCase() != 'otlp') {
    throw StateError(
      'local telemetry requires OTEL_TRACES_EXPORTER=otlp, got '
      '$tracesExporter.',
    );
  }
  final protocol =
      Platform.environment['OTEL_EXPORTER_OTLP_PROTOCOL'] ?? 'http/protobuf';
  if (protocol.trim().toLowerCase() != 'http/protobuf') {
    throw StateError(
      'local telemetry requires OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf, '
      'got $protocol.',
    );
  }

  LocalTelemetry? telemetry;
  try {
    telemetry = await LocalTelemetry.start(
      endpoint: otlpEndpoint,
      serviceName: _serviceName,
    );
    implementation.stemLogger.addChannel('otlp', OTelLogDriver());
    // Built-in lifecycle diagnostics are debug-level. Keep normal console
    // output and export those real records alongside the task's application log.
    implementation.configureStemLogging(level: Level.debug);

    final app = await StemWorkflowApp.inMemory(
      scripts: [_checkpointScript],
      tasks: [_localTask, _retryTask, _failureTask, _fanoutTask],
      pollInterval: const Duration(milliseconds: 10),
    );

    try {
      await app.start();
      final runIds = await Future.wait([
        _checkpointScript.start(app),
        _checkpointScript.start(app),
      ]);
      final operation = await StemTracer.instance.trace<_TaskRun>(
        'local telemetry task operation',
        () async {
          final traceId = StemTracer.instance.traceFields()['traceId'];
          final taskId = await app.enqueue(
            _localTask.name,
            args: const {'value': 'smoke'},
          );
          final result = await app.waitForTask<String>(
            taskId,
            timeout: const Duration(seconds: 10),
          );
          return _TaskRun(traceId: traceId, taskId: taskId, result: result);
        },
      );

      final workflowResults = Future.wait<WorkflowResult<String>?>(
        runIds.map(
          (runId) => _checkpointScript.waitFor(
            app,
            runId,
            timeout: const Duration(seconds: 10),
          ),
        ),
      );
      final workflows = await workflowResults;
      final taskValue = operation.result?.value;
      if (operation.traceId == null ||
          taskValue == null ||
          !taskValue.contains(operation.traceId!)) {
        throw StateError(
          'Task trace propagation mismatch: root=${operation.traceId}, '
          'result=$taskValue',
        );
      }

      final retry = await _runTaskScenario(app, _retryTask.name);
      if (retry.result?.value != 'retry-succeeded-attempt-1' ||
          retry.result?.status.attempt != 1) {
        throw StateError(
          'Retry scenario did not succeed on its second attempt.',
        );
      }
      final failure = await _runTaskScenario(app, _failureTask.name);
      if (failure.result?.isFailed != true) {
        throw StateError('Intentional failure did not reach terminal failure.');
      }

      String? fanoutTraceId;
      await StemTracer.instance.trace<void>('local telemetry fanout', () async {
        fanoutTraceId = StemTracer.instance.traceFields()['traceId'];
        final group = await app.app.canvas.group<String>([
          task<String>(_fanoutTask.name, args: const {'branch': 'a'}),
          task<String>(_fanoutTask.name, args: const {'branch': 'b'}),
        ]);
        try {
          final results = await group.results.toList().timeout(
            const Duration(seconds: 10),
          );
          final values = results.map((result) => result.value).toSet();
          if (results.length != 2 ||
              !results.every((result) => result.isSucceeded) ||
              !values.containsAll({'branch-a', 'branch-b'})) {
            throw StateError('Canvas fan-out did not complete both branches.');
          }
        } finally {
          await group.dispose();
        }
      });

      print('service.name=$_serviceName');
      print('workflow=local-traces.checkpoint-script runs=${runIds.length}');
      print(
        'workflow.results=${workflows.map((r) => r?.requiredValue()).join(',')}',
      );
      print(
        'task=${_localTask.name} id=${operation.taskId} '
        'result=$taskValue',
      );
      print('propagation.traceId=${operation.traceId}');
      print('retry.traceId=${retry.traceId} taskId=${retry.taskId}');
      print('failure.traceId=${failure.traceId} taskId=${failure.taskId}');
      print('fanout.traceId=$fanoutTraceId branches=2');
      await app.close();
      print('worker.drain=complete');
      print('OTLP traces: $otlpEndpoint; viewer UI: http://127.0.0.1:8000');
    } finally {
      await app.close();
    }
  } finally {
    if (telemetry != null) {
      // Stem is drained above before SDK processors are flushed and shut down.
      await telemetry.flush();
    }
  }
}

Future<_TaskRun> _runTaskScenario(StemWorkflowApp app, String taskName) =>
    StemTracer.instance.trace<_TaskRun>('local scenario: $taskName', () async {
      final traceId = StemTracer.instance.traceFields()['traceId'];
      final taskId = await app.enqueue(taskName);
      final result = await app.waitForTask<String>(
        taskId,
        timeout: const Duration(seconds: 10),
      );
      if (traceId == null || result == null || result.timedOut) {
        throw StateError('Scenario $taskName did not finish with a trace.');
      }
      return _TaskRun(traceId: traceId, taskId: taskId, result: result);
    });

class _TaskRun {
  const _TaskRun({
    required this.traceId,
    required this.taskId,
    required this.result,
  });

  final String? traceId;
  final String taskId;
  final TaskResult<String>? result;
}
