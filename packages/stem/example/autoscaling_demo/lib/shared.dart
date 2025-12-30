import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

const autoscaleQueue = 'autoscale';

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
      name: 'autoscale.work',
      options: const TaskOptions(queue: autoscaleQueue),
      entrypoint: _autoscaleEntrypoint,
    ),
  );
  return registry;
}

FutureOr<void> _autoscaleEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  final label = (args['label'] as String?) ?? 'autoscale';
  final durationMs = (args['durationMs'] as num?)?.toInt() ?? 900;

  stdout.writeln(
    '[task] start label=$label durationMs=$durationMs attempt=${context.attempt}',
  );
  context.heartbeat();
  await Future<void>.delayed(Duration(milliseconds: durationMs));
  stdout.writeln('[task] done label=$label');
  context.progress(1.0, data: {'label': label});
}
