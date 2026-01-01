import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

const controlQueue = 'control';

Future<RedisStreamsBroker> connectBroker(String url) {
  return RedisStreamsBroker.connect(url);
}

Future<RedisResultBackend> connectBackend(String url) {
  return RedisResultBackend.connect(url);
}

Future<RedisRevokeStore> connectRevokeStore(String url) {
  return RedisRevokeStore.connect(url, namespace: 'stem');
}

SimpleTaskRegistry buildRegistry() {
  final registry = SimpleTaskRegistry();
  registry
    ..register(ControlLongTask())
    ..register(ControlQuickTask());
  return registry;
}

class ControlLongTask extends TaskHandler<String> {
  @override
  String get name => 'control.long';

  @override
  TaskOptions get options => const TaskOptions(queue: controlQueue);

  @override
  TaskMetadata get metadata => const TaskMetadata(
        description: 'Long-running task that emits heartbeats and progress.',
        tags: ['control', 'long-running'],
      );

  @override
  Future<String> call(TaskContext context, Map<String, Object?> args) async {
    final label = (args['label'] as String?) ?? context.id;
    final steps = (args['steps'] as num?)?.toInt() ?? 12;
    final delayMs = (args['delayMs'] as num?)?.toInt() ?? 1000;

    stdout.writeln(
      '[task][long][start] id=${context.id} label=$label steps=$steps',
    );

    for (var i = 0; i < steps; i += 1) {
      context.heartbeat();
      await context.progress(
        (i + 1) / steps,
        data: {'step': i + 1, 'label': label},
      );
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }

    stdout.writeln('[task][long][done] id=${context.id} label=$label');
    return 'done';
  }
}

class ControlQuickTask extends TaskHandler<String> {
  @override
  String get name => 'control.quick';

  @override
  TaskOptions get options => const TaskOptions(queue: controlQueue);

  @override
  TaskMetadata get metadata => const TaskMetadata(
        description: 'Short task for baseline worker throughput.',
        tags: ['control', 'quick'],
      );

  @override
  Future<String> call(TaskContext context, Map<String, Object?> args) async {
    final label = (args['label'] as String?) ?? context.id;
    stdout.writeln('[task][quick] id=${context.id} label=$label');
    await context.progress(1.0, data: {'label': label});
    return 'ok';
  }
}
