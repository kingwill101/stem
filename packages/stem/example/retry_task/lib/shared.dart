import 'dart:async';
import 'dart:convert';

import 'package:stem/stem.dart';

SimpleTaskRegistry buildRegistry() {
  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<void>(
        name: 'tasks.always_fail',
        entrypoint: _alwaysFailEntrypoint,
        options: const TaskOptions(maxRetries: 2, queue: 'retry-demo'),
      ),
    );
  return registry;
}

List<SignalSubscription> attachLogging(String label) {
  String prefix(String event) => '[retry][$label][$event]';

  void log(String event, Map<String, Object?> data) {
    // ignore: avoid_print
    print('${prefix(event)} ${jsonEncode(data)}');
  }

  return <SignalSubscription>[
    StemSignals.onBeforeTaskPublish((payload, context) {
      log('before_task_publish', {
        'task': payload.envelope.name,
        'id': payload.envelope.id,
        'attempt': payload.attempt,
        'sender': context.sender,
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
    StemSignals.onTaskRetry((payload, _) {
      log('task_retry', {
        'task': payload.envelope.name,
        'id': payload.envelope.id,
        'attempt': payload.attempt,
        'reason': payload.reason.toString(),
        'nextRunAt': payload.nextRetryAt.toIso8601String(),
        'worker': payload.worker.id,
      });
    }),
    StemSignals.onTaskFailure((payload, _) {
      log('task_failed', {
        'task': payload.envelope.name,
        'id': payload.envelope.id,
        'attempt': payload.attempt,
        'worker': payload.worker.id,
        'error': payload.error.toString(),
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
  ];
}

FutureOr<void> _alwaysFailEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) {
  final attempt = context.attempt;
  final max = context.meta['maxRetries'] ?? 3;
  // ignore: avoid_print
  print('[retry][task][attempt] {"attempt":$attempt,"max":$max}');
  throw StateError('Simulated failure on attempt $attempt');
}
