import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

import 'package:stem_signals_demo/shared.dart';

Future<void> main() async {
  final brokerUrl =
      Platform.environment['STEM_BROKER_URL'] ?? 'redis://redis:6379/0';

  registerSignalLogging('producer');

  final broker = await RedisStreamsBroker.connect(brokerUrl);
  final registry = buildRegistry();
  final stem = Stem(
    broker: broker,
    registry: registry,
    backend: InMemoryResultBackend(),
  );

  final timer = Timer.periodic(const Duration(seconds: 5), (_) async {
    await stem.enqueue(
      'tasks.hello',
      args: {'name': 'from-producer'},
    );
    await stem.enqueue('tasks.flaky');
    await stem.enqueue('tasks.always_fail');
  });

  void scheduleShutdown(ProcessSignal signal) async {
    // ignore: avoid_print
    print('[signals][producer] received $signal, shutting down');
    timer.cancel();
    await broker.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(scheduleShutdown);
  ProcessSignal.sigterm.watch().listen(scheduleShutdown);

  await Completer<void>().future;
}
