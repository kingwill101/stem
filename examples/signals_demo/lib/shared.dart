import 'dart:async';
import 'dart:convert';

import 'package:stem/stem.dart';

SimpleTaskRegistry buildRegistry() {
  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<String>(
        name: 'tasks.hello',
        entrypoint: _helloEntrypoint,
        options: const TaskOptions(maxRetries: 0),
      ),
    )
    ..register(
      FunctionTaskHandler<String>(
        name: 'tasks.flaky',
        entrypoint: _flakyEntrypoint,
        options: const TaskOptions(maxRetries: 2),
      ),
    )
    ..register(
      FunctionTaskHandler<void>(
        name: 'tasks.always_fail',
        entrypoint: _alwaysFailEntrypoint,
        options: const TaskOptions(maxRetries: 1),
      ),
    );
  return registry;
}

List<SignalSubscription> registerSignalLogging(String label) {
  String prefix(String event) => '[signals][$label][$event]';

  String encode(Map<String, Object?> data) {
    return jsonEncode(
      data.map(
        (key, value) => MapEntry(
          key,
          value is DateTime ? value.toIso8601String() : value,
        ),
      ),
    );
  }

  void log(String event, Map<String, Object?> payload) {
    // ignore: avoid_print
    print('${prefix(event)} ${encode(payload)}');
  }

  final subscriptions = <SignalSubscription>[
    StemSignals.onBeforeTaskPublish((payload, ctx) {
      log('before_task_publish', {
        'task': payload.envelope.name,
        'id': payload.envelope.id,
        'attempt': payload.attempt,
        'sender': ctx.sender,
      });
    }),
    StemSignals.onAfterTaskPublish((payload, ctx) {
      log('after_task_publish', {
        'task': payload.envelope.name,
        'id': payload.taskId,
        'attempt': payload.attempt,
        'sender': ctx.sender,
      });
    }),
    StemSignals.onTaskReceived((payload, _) {
      log('task_received', {
        'task': payload.envelope.name,
        'id': payload.envelope.id,
        'worker': payload.worker.id,
      });
    }),
    StemSignals.onTaskPrerun((payload, _) {
      log('task_prerun', {
        'task': payload.envelope.name,
        'id': payload.envelope.id,
        'attempt': payload.context.attempt,
        'worker': payload.worker.id,
      });
    }),
    StemSignals.onTaskPostrun((payload, _) {
      log('task_postrun', {
        'task': payload.envelope.name,
        'id': payload.envelope.id,
        'state': payload.state.name,
        'worker': payload.worker.id,
      });
    }),
    StemSignals.onTaskSuccess((payload, _) {
      log('task_success', {
        'task': payload.envelope.name,
        'id': payload.envelope.id,
        'result': payload.result,
        'worker': payload.worker.id,
      });
    }),
    StemSignals.onTaskFailure((payload, _) {
      log('task_failure', {
        'task': payload.envelope.name,
        'id': payload.envelope.id,
        'error': payload.error.toString(),
        'worker': payload.worker.id,
      });
    }),
    StemSignals.onTaskRetry((payload, _) {
      log('task_retry', {
        'task': payload.envelope.name,
        'id': payload.envelope.id,
        'reason': payload.reason.toString(),
        'nextRunAt': payload.nextRetryAt,
        'worker': payload.worker.id,
      });
    }),
    StemSignals.onTaskRevoked((payload, _) {
      log('task_revoked', {
        'task': payload.envelope.name,
        'id': payload.envelope.id,
        'reason': payload.reason,
        'worker': payload.worker.id,
      });
    }),
    StemSignals.workerInit.connect((payload, _) {
      log('worker_init', {
        'worker': payload.worker.id,
        'queues': payload.worker.queues,
      });
    }),
    StemSignals.workerReady.connect((payload, _) {
      log('worker_ready', {
        'worker': payload.worker.id,
        'queues': payload.worker.queues,
      });
    }),
    StemSignals.workerStopping.connect((payload, _) {
      log('worker_stopping', {
        'worker': payload.worker.id,
        'reason': payload.reason,
      });
    }),
    StemSignals.workerShutdown.connect((payload, _) {
      log('worker_shutdown', {
        'worker': payload.worker.id,
        'reason': payload.reason,
      });
    }),
    StemSignals.workerHeartbeat.connect((payload, _) {
      log('worker_heartbeat', {
        'worker': payload.worker.id,
        'timestamp': payload.timestamp.toIso8601String(),
      });
    }),
    StemSignals.workerChildInit.connect((payload, _) {
      log('worker_child_init', {
        'worker': payload.worker.id,
        'isolateId': payload.isolateId,
      });
    }),
    StemSignals.workerChildShutdown.connect((payload, _) {
      log('worker_child_shutdown', {
        'worker': payload.worker.id,
        'isolateId': payload.isolateId,
      });
    }),
    StemSignals.scheduleEntryDue.connect((payload, _) {
      log('schedule_entry_due', {
        'id': payload.entry.id,
        'task': payload.entry.taskName,
      });
    }),
    StemSignals.scheduleEntryDispatched.connect((payload, _) {
      log('schedule_entry_dispatched', {
        'id': payload.entry.id,
        'task': payload.entry.taskName,
        'driftMs': payload.drift.inMilliseconds,
      });
    }),
    StemSignals.scheduleEntryFailed.connect((payload, _) {
      log('schedule_entry_failed', {
        'id': payload.entry.id,
        'task': payload.entry.taskName,
        'error': payload.error.toString(),
      });
    }),
    StemSignals.controlCommandReceived.connect((payload, _) {
      log('control_command_received', {
        'worker': payload.worker.id,
        'type': payload.command.type,
        'requestId': payload.command.requestId,
      });
    }),
    StemSignals.controlCommandCompleted.connect((payload, _) {
      log('control_command_completed', {
        'worker': payload.worker.id,
        'type': payload.command.type,
        'requestId': payload.command.requestId,
        'status': payload.status,
      });
    }),
  ];

  return subscriptions;
}

FutureOr<String> _helloEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  final name = (args['name'] as String?) ?? 'friend';
  context.heartbeat();
  return 'Hello $name!';
}

FutureOr<String> _flakyEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  if (context.attempt == 0) {
    throw StateError('first attempt always fails');
  }
  return 'Recovered on attempt ${context.attempt}';
}

FutureOr<void> _alwaysFailEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) {
  throw StateError('this task always fails');
}
