import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_autoscaling_demo/shared.dart';

Future<void> main() async {
  final config = StemConfig.fromEnvironment();
  final broker = await connectBroker(config.brokerUrl, tls: config.tls);
  final backendUrl = config.resultBackendUrl ?? config.brokerUrl;
  final backend = await connectBackend(backendUrl, tls: config.tls);

  final registry = buildRegistry();
  final observability = ObservabilityConfig.fromEnvironment();

  final workerName =
      Platform.environment['WORKER_NAME'] ?? 'autoscale-worker-${pid}';
  final concurrency = _parseInt('WORKER_CONCURRENCY', fallback: 6, min: 1);

  final autoscale = WorkerAutoscaleConfig(
    enabled: true,
    minConcurrency: _parseInt('AUTOSCALE_MIN', fallback: 1, min: 1),
    maxConcurrency: _parseOptionalInt('AUTOSCALE_MAX'),
    scaleUpStep: _parseInt('AUTOSCALE_SCALE_UP_STEP', fallback: 1, min: 1),
    scaleDownStep: _parseInt('AUTOSCALE_SCALE_DOWN_STEP', fallback: 1, min: 1),
    backlogPerIsolate: _parseDouble(
      'AUTOSCALE_BACKLOG_PER_ISOLATE',
      fallback: 2.0,
      min: 0.1,
    ),
    idlePeriod: _parseDuration('AUTOSCALE_IDLE_MS', fallbackMs: 4000),
    tick: _parseDuration('AUTOSCALE_TICK_MS', fallbackMs: 1000),
    scaleUpCooldown:
        _parseDuration('AUTOSCALE_UP_COOLDOWN_MS', fallbackMs: 2000),
    scaleDownCooldown:
        _parseDuration('AUTOSCALE_DOWN_COOLDOWN_MS', fallbackMs: 3000),
  );

  stdout.writeln(
    '[worker] broker=${config.brokerUrl} backend=$backendUrl '
    'concurrency=$concurrency autoscale(min=${autoscale.minConcurrency}, '
    'max=${autoscale.maxConcurrency ?? concurrency})',
  );

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    queue: autoscaleQueue,
    subscription: RoutingSubscription.singleQueue(autoscaleQueue),
    consumerName: workerName,
    concurrency: concurrency,
    autoscale: autoscale,
    prefetchMultiplier: 1,
    observability: observability,
  );

  await worker.start();
  stdout.writeln('[worker] listening on queue "$autoscaleQueue"');

  Future<void> shutdown(ProcessSignal signal) async {
    stdout.writeln('[worker] received $signal, shutting down...');
    await worker.shutdown(mode: WorkerShutdownMode.warm);
    await broker.close();
    await backend.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  ProcessSignal.sigterm.watch().listen(shutdown);

  await Completer<void>().future;
}

int _parseInt(String key, {required int fallback, int min = 0}) {
  final raw = Platform.environment[key];
  if (raw == null || raw.trim().isEmpty) return fallback;
  final parsed = int.tryParse(raw.trim());
  if (parsed == null || parsed < min) return fallback;
  return parsed;
}

int? _parseOptionalInt(String key) {
  final raw = Platform.environment[key];
  if (raw == null || raw.trim().isEmpty) return null;
  final parsed = int.tryParse(raw.trim());
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}

double _parseDouble(
  String key, {
  required double fallback,
  double min = 0,
}) {
  final raw = Platform.environment[key];
  if (raw == null || raw.trim().isEmpty) return fallback;
  final parsed = double.tryParse(raw.trim());
  if (parsed == null || parsed < min) return fallback;
  return parsed;
}

Duration _parseDuration(String key, {required int fallbackMs}) {
  final raw = Platform.environment[key];
  if (raw == null || raw.trim().isEmpty) {
    return Duration(milliseconds: fallbackMs);
  }
  final parsed = int.tryParse(raw.trim());
  if (parsed == null || parsed <= 0) {
    return Duration(milliseconds: fallbackMs);
  }
  return Duration(milliseconds: parsed);
}
