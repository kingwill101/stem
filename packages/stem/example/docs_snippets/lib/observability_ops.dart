// Observability and ops snippets for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

// #region ops-heartbeats
Future<void> listWorkerHeartbeats() async {
  final backend = await RedisResultBackend.connect(
    Platform.environment['STEM_RESULT_BACKEND_URL']!,
  );
  final heartbeats = await backend.listWorkerHeartbeats();
  for (final hb in heartbeats) {
    print('${hb.workerId} -> queues=${hb.queues} inflight=${hb.inflight}');
  }
  await backend.close();
}
// #endregion ops-heartbeats

// #region ops-analytics
void installAnalytics() {
  StemSignals.taskRetry.connect((payload, _) {
    print('Task ${payload.envelope.name} retry ${payload.attempt}');
  });

  StemSignals.workerHeartbeat.connect((payload, _) {
    if (payload.worker.queues.length > 100) {
      // Send to your alerting system.
    }
  });

  StemSignals.scheduleEntryFailed.connect((payload, _) {
    print('Scheduler entry ${payload.entry.id} failed: ${payload.error}');
  });
}
// #endregion ops-analytics

Future<void> main() async {
  installAnalytics();

  final backendUrl = Platform.environment['STEM_RESULT_BACKEND_URL'];
  if (backendUrl == null || backendUrl.isEmpty) {
    print('Set STEM_RESULT_BACKEND_URL to list worker heartbeats.');
    return;
  }
  await listWorkerHeartbeats();
}
