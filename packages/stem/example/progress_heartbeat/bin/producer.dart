import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_progress_heartbeat/shared.dart';

Future<void> main() async {
  final brokerUrl =
      Platform.environment['STEM_BROKER_URL'] ?? 'redis://localhost:6379/0';
  final backendUrl = Platform.environment['STEM_RESULT_BACKEND_URL'] ??
      'redis://localhost:6379/1';
  final taskCount = int.tryParse(Platform.environment['TASKS'] ?? '') ?? 1;
  final steps = int.tryParse(Platform.environment['STEPS'] ?? '') ?? 10;
  final delayMs =
      int.tryParse(Platform.environment['STEP_DELAY_MS'] ?? '') ?? 800;

  stdout.writeln(
    '[producer] broker=$brokerUrl backend=$backendUrl tasks=$taskCount',
  );

  final broker = await connectBroker(brokerUrl);
  final backend = await connectBackend(backendUrl);
  final registry = buildRegistry();

  final stem = Stem(
    broker: broker,
    registry: registry,
    backend: backend,
  );
  const taskOptions = TaskOptions(queue: progressQueue);

  for (var i = 0; i < taskCount; i += 1) {
    final id = await stem.enqueue(
      'progress.demo',
      options: taskOptions,
      args: {'steps': steps, 'delayMs': delayMs},
    );
    stdout.writeln('[producer] enqueued progress.demo id=$id');
  }

  await broker.close();
  await backend.close();
}
