import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

const progressQueue = 'progress';

Future<RedisStreamsBroker> connectBroker(String url) {
  return RedisStreamsBroker.connect(url);
}

Future<RedisResultBackend> connectBackend(String url) {
  return RedisResultBackend.connect(url);
}

SimpleTaskRegistry buildRegistry() {
  final registry = SimpleTaskRegistry();
  registry.register(ProgressTask());
  return registry;
}

// #region reliability-worker-event-logging
void attachWorkerEventLogging(Worker worker) {
  worker.events.listen((event) {
    switch (event.type) {
      case WorkerEventType.progress:
        stdout.writeln(
          '[event][progress] id=${event.envelope?.id} progress=${event.progress} data=${event.data}',
        );
        break;
      case WorkerEventType.heartbeat:
        stdout.writeln('[event][heartbeat] id=${event.envelopeId}');
        break;
      case WorkerEventType.completed:
        stdout.writeln('[event][completed] id=${event.envelope?.id}');
        break;
      case WorkerEventType.failed:
        stdout.writeln('[event][failed] id=${event.envelope?.id}');
        break;
      case WorkerEventType.revoked:
        stdout.writeln('[event][revoked] id=${event.envelope?.id}');
        break;
      case WorkerEventType.retried:
      case WorkerEventType.timeout:
      case WorkerEventType.error:
        stdout.writeln('[event][${event.type.name}] id=${event.envelope?.id}');
        break;
    }
  });
}
// #endregion reliability-worker-event-logging

// #region reliability-progress-task
class ProgressTask extends TaskHandler<String> {
  @override
  String get name => 'progress.demo';

  @override
  TaskOptions get options => const TaskOptions(queue: progressQueue);

  @override
  TaskMetadata get metadata => const TaskMetadata(
        description: 'Task that reports progress and heartbeats on a loop.',
        tags: ['progress', 'heartbeat'],
      );

  @override
  Future<String> call(TaskContext context, Map<String, Object?> args) async {
    final steps = (args['steps'] as num?)?.toInt() ?? 10;
    final delayMs = (args['delayMs'] as num?)?.toInt() ?? 800;

    stdout.writeln('[task][start] id=${context.id} steps=$steps');

    for (var i = 0; i < steps; i += 1) {
      context.heartbeat();
      await context.progress(
        (i + 1) / steps,
        data: {'step': i + 1, 'total': steps},
      );
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }

    stdout.writeln('[task][done] id=${context.id}');
    return 'ok';
  }
}
// #endregion reliability-progress-task
