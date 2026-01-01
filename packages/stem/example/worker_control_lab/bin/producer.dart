import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_worker_control_lab/shared.dart';

Future<void> main() async {
  final brokerUrl =
      Platform.environment['STEM_BROKER_URL'] ?? 'redis://localhost:6379/0';
  final backendUrl = Platform.environment['STEM_RESULT_BACKEND_URL'] ??
      'redis://localhost:6379/1';
  final longCount = int.tryParse(Platform.environment['LONG_TASKS'] ?? '') ?? 2;
  final quickCount =
      int.tryParse(Platform.environment['QUICK_TASKS'] ?? '') ?? 1;
  final steps =
      int.tryParse(Platform.environment['LONG_TASK_STEPS'] ?? '') ?? 12;
  final outputPath = Platform.environment['TASK_ID_FILE'];

  stdout.writeln(
    '[producer] broker=$brokerUrl backend=$backendUrl long=$longCount quick=$quickCount',
  );

  final broker = await connectBroker(brokerUrl);
  final backend = await connectBackend(backendUrl);
  final registry = buildRegistry();

  final stem = Stem(
    broker: broker,
    registry: registry,
    backend: backend,
  );

  final ids = <String>[];
  const taskOptions = TaskOptions(queue: controlQueue);

  for (var i = 0; i < longCount; i += 1) {
    final label = 'long-${i + 1}';
    final id = await stem.enqueue(
      'control.long',
      options: taskOptions,
      args: {'label': label, 'steps': steps},
    );
    ids.add(id);
    stdout.writeln('[producer] enqueued control.long id=$id label=$label');
  }

  for (var i = 0; i < quickCount; i += 1) {
    final label = 'quick-${i + 1}';
    final id = await stem.enqueue(
      'control.quick',
      options: taskOptions,
      args: {'label': label},
    );
    ids.add(id);
    stdout.writeln('[producer] enqueued control.quick id=$id label=$label');
  }

  if (outputPath != null && outputPath.trim().isNotEmpty) {
    final file = File(outputPath);
    await file.writeAsString(ids.join('\n'));
    stdout.writeln('[producer] wrote ${ids.length} task ids to ${file.path}');
  }

  await broker.close();
  await backend.close();
}
