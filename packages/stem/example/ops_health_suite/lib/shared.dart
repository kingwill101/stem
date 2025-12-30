import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

const opsQueue = 'ops';

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
      name: 'ops.ping',
      options: const TaskOptions(queue: opsQueue),
      entrypoint: _opsEntrypoint,
    ),
  );
  return registry;
}

FutureOr<void> _opsEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  final label = (args['label'] as String?) ?? 'ops';
  final delayMs = (args['delayMs'] as num?)?.toInt() ?? 500;
  stdout.writeln('[task] $label start');
  context.heartbeat();
  await Future<void>.delayed(Duration(milliseconds: delayMs));
  context.progress(1.0, data: {'label': label});
  stdout.writeln('[task] $label done');
}
