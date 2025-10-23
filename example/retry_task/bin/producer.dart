import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_retry_task_demo/shared.dart';

Future<void> main() async {
  final brokerUrl =
      Platform.environment['STEM_BROKER_URL'] ?? 'redis://redis:6379/0';

  final broker = await RedisStreamsBroker.connect(brokerUrl);
  final registry = buildRegistry();
  final subscriptions = attachLogging('producer');
  final stem = Stem(broker: broker, registry: registry);

  final taskId = await stem.enqueue(
    'tasks.always_fail',
    options: const TaskOptions(maxRetries: 3, queue: 'retry-demo'),
    meta: const {'maxRetries': 3},
  );

  // ignore: avoid_print
  print('[retry][producer][enqueued] {"taskId":"$taskId"}');

  for (final sub in subscriptions) {
    sub.cancel();
  }

  await Future<void>.delayed(const Duration(seconds: 1));
  await broker.close();
}
