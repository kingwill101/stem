import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

const scheduleQueue = 'scheduled';

Future<RedisStreamsBroker> connectBroker(String url, {TlsConfig? tls}) {
  return RedisStreamsBroker.connect(url, tls: tls);
}

Future<RedisResultBackend> connectBackend(String url, {TlsConfig? tls}) {
  return RedisResultBackend.connect(url, tls: tls);
}

SimpleTaskRegistry buildRegistry() {
  final registry = SimpleTaskRegistry();
  registry.register(
    FunctionTaskHandler<void>(
      name: 'scheduler.demo',
      options: const TaskOptions(queue: scheduleQueue),
      entrypoint: _scheduledEntrypoint,
    ),
  );
  return registry;
}

FutureOr<void> _scheduledEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  final label = (args['label'] as String?) ?? 'scheduled';
  final workMs = (args['workMs'] as num?)?.toInt() ?? 400;
  stdout.writeln('[task] $label fired');
  context.heartbeat();
  await Future<void>.delayed(Duration(milliseconds: workMs));
  context.progress(1.0, data: {'label': label});
}
