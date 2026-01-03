import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_task_context_mixed_example/shared.dart';
import 'package:stem_sqlite/stem_sqlite.dart';

Future<void> main() async {
  final broker = await connectBroker();
  final backend = await connectBackend();
  final registry = buildRegistry();

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    queue: mixedQueue,
    consumerName: Platform.environment['WORKER_NAME'] ?? 'task-context-worker',
    concurrency: 2,
    prefetchMultiplier: 1,
  );

  ProcessSignal.sigint.watch().listen((_) {
    stdout.writeln('Shutdown requested.');
    unawaited(_shutdown(worker, broker, backend));
  });
  ProcessSignal.sigterm.watch().listen((_) {
    stdout.writeln('Shutdown requested.');
    unawaited(_shutdown(worker, broker, backend));
  });

  final paths = resolveDatabasePaths();
  stdout.writeln(
    'Worker started. SQLite broker: ${paths.broker.absolute.path} backend: ${paths.backend.absolute.path}',
  );
  await worker.start();
}

Future<void> _shutdown(
  Worker worker,
  SqliteBroker broker,
  SqliteResultBackend backend,
) async {
  await worker.shutdown(mode: WorkerShutdownMode.warm);
  await broker.close();
  await backend.close();
  exit(0);
}
