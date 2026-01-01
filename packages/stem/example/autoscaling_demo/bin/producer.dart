import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_autoscaling_demo/shared.dart';

Future<void> main() async {
  final config = StemConfig.fromEnvironment();
  final broker = await connectBroker(config.brokerUrl, tls: config.tls);
  final backendUrl = config.resultBackendUrl ?? config.brokerUrl;
  final backend = await connectBackend(backendUrl, tls: config.tls);
  final registry = buildRegistry();

  final taskCount = _parseInt('TASKS', fallback: 48, min: 1);
  final burst = _parseInt('BURST', fallback: 12, min: 1);
  final pauseMs = _parseInt('PAUSE_MS', fallback: 1200, min: 0);
  final durationMs = _parseInt('TASK_DURATION_MS', fallback: 900, min: 50);
  final initialDelayMs = _parseInt('START_DELAY_MS', fallback: 500, min: 0);

  stdout.writeln(
    '[producer] broker=${config.brokerUrl} backend=$backendUrl '
    'tasks=$taskCount burst=$burst pauseMs=$pauseMs durationMs=$durationMs',
  );

  final stem = Stem(broker: broker, registry: registry, backend: backend);
  const options = TaskOptions(queue: autoscaleQueue);

  if (initialDelayMs > 0) {
    await Future<void>.delayed(Duration(milliseconds: initialDelayMs));
  }

  for (var i = 0; i < taskCount; i += 1) {
    final label = 'job-${i + 1}';
    final id = await stem.enqueue(
      'autoscale.work',
      options: options,
      args: {'label': label, 'durationMs': durationMs},
    );
    stdout.writeln('[producer] enqueued $label id=$id');
    if ((i + 1) % burst == 0 && i + 1 < taskCount && pauseMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: pauseMs));
    }
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
