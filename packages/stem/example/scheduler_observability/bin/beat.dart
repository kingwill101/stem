import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';
import 'package:stem_scheduler_observability/shared.dart';

Future<void> main() async {
  final config = StemConfig.fromEnvironment();
  final broker = await connectBroker(config.brokerUrl, tls: config.tls);
  final scheduleUrl = config.scheduleStoreUrl ?? config.brokerUrl;
  final store = await RedisScheduleStore.connect(scheduleUrl, tls: config.tls);
  final lockStore = await RedisLockStore.connect(scheduleUrl, tls: config.tls);
  final signer = PayloadSigner.maybe(config.signing);

  final observability = ObservabilityConfig.fromEnvironment();
  observability.applyMetricExporters();
  observability.applySignalConfiguration();

  StemSignals.scheduleEntryDue.connect((payload, _) {
    stdout.writeln(
      '[signal] schedule due id=${payload.entry.id} tick=${payload.tickAt.toIso8601String()}',
    );
  });
  StemSignals.scheduleEntryDispatched.connect((payload, _) {
    stdout.writeln(
      '[signal] schedule dispatched id=${payload.entry.id} drift=${payload.drift.inMilliseconds}ms',
    );
  });
  StemSignals.scheduleEntryFailed.connect((payload, _) {
    stdout.writeln(
      '[signal] schedule failed id=${payload.entry.id} error=${payload.error}',
    );
  });

  final beat = Beat(
    store: store,
    broker: broker,
    lockStore: lockStore,
    tickInterval: const Duration(seconds: 1),
    signer: signer,
  );

  await beat.start();
  stdout.writeln(
    '[beat] started broker=${config.brokerUrl} scheduleStore=$scheduleUrl',
  );

  Future<void> shutdown(ProcessSignal signal) async {
    stdout.writeln('[beat] received $signal, shutting down...');
    await beat.stop();
    await store.close();
    await lockStore.close();
    await broker.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  ProcessSignal.sigterm.watch().listen(shutdown);

  await Completer<void>().future;
}
