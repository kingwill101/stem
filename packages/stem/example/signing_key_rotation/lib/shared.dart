import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

const rotationQueue = 'rotation';

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
      name: 'rotation.demo',
      options: const TaskOptions(queue: rotationQueue),
      entrypoint: _rotationEntrypoint,
    ),
  );
  return registry;
}

FutureOr<void> _rotationEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  final label = (args['label'] as String?) ?? 'rotation';
  stdout.writeln('[task] processed $label');
  context.progress(1.0, data: {'label': label});
}
