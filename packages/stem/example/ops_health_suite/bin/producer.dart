import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_ops_health_suite/shared.dart';

Future<void> main() async {
  final config = StemConfig.fromEnvironment();
  final broker = await connectBroker(config.brokerUrl, tls: config.tls);
  final backendUrl = config.resultBackendUrl ?? config.brokerUrl;
  final backend = await connectBackend(backendUrl, tls: config.tls);
  final registry = buildRegistry();

  final taskCount = _parseInt('TASKS', fallback: 6, min: 1);
  final delayMs = _parseInt('DELAY_MS', fallback: 400, min: 0);

  stdout.writeln(
    '[producer] broker=${config.brokerUrl} backend=$backendUrl tasks=$taskCount',
  );

  final stem = Stem(broker: broker, registry: registry, backend: backend);
  const options = TaskOptions(queue: opsQueue);

  for (var i = 0; i < taskCount; i += 1) {
    final label = 'health-${i + 1}';
    final id = await stem.enqueue(
      'ops.ping',
      options: options,
      args: {'label': label, 'delayMs': delayMs},
    );
    stdout.writeln('[producer] enqueued $label id=$id');
  }

  await broker.close();
  await backend.close();
}

int _parseInt(String key, {required int fallback, int min = 0}) {
  final raw = Platform.environment[key];
  if (raw == null || raw.trim().isEmpty) return fallback;
  final parsed = int.tryParse(raw.trim());
  if (parsed == null || parsed < min) return fallback;
  return parsed;
}
