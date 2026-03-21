import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';
import 'package:stem_ops_health_suite/shared.dart';

Future<void> main() async {
  final config = StemConfig.fromEnvironment();
  final backendUrl = config.resultBackendUrl ?? config.brokerUrl;
  final client = await StemClient.fromUrl(
    config.brokerUrl,
    adapters: [StemRedisAdapter(tls: config.tls)],
    overrides: StemStoreOverrides(backend: backendUrl),
    tasks: buildTasks(),
  );

  final taskCount = _parseInt('TASKS', fallback: 6, min: 1);
  final delayMs = _parseInt('DELAY_MS', fallback: 400, min: 0);

  stdout.writeln(
    '[producer] broker=${config.brokerUrl} backend=$backendUrl tasks=$taskCount',
  );

  const options = TaskOptions(queue: opsQueue);

  for (var i = 0; i < taskCount; i += 1) {
    final label = 'health-${i + 1}';
    final id = await client.enqueue(
      'ops.ping',
      options: options,
      args: {'label': label, 'delayMs': delayMs},
    );
    stdout.writeln('[producer] enqueued $label id=$id');
  }

  await client.close();
}

int _parseInt(String key, {required int fallback, int min = 0}) {
  final raw = Platform.environment[key];
  if (raw == null || raw.trim().isEmpty) return fallback;
  final parsed = int.tryParse(raw.trim());
  if (parsed == null || parsed < min) return fallback;
  return parsed;
}
