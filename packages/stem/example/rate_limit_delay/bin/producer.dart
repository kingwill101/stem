import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_rate_limit_delay_demo/shared.dart';

Future<void> main() async {
  final brokerUrl =
      Platform.environment['STEM_BROKER_URL'] ?? 'redis://localhost:6381/0';
  final backendUrl = Platform.environment['STEM_RESULT_BACKEND_URL'] ??
      'redis://localhost:6381/1';

  stdout.writeln('[producer] connecting broker=$brokerUrl backend=$backendUrl');

  final broker = await connectBroker(brokerUrl);
  final backend = await connectBackend(backendUrl);
  final registry = buildRegistry();
  final routing = buildRoutingRegistry();
  final stem = buildStem(
    broker: broker,
    registry: registry,
    backend: backend,
    routing: routing,
  );

  final totalJobs =
      int.tryParse(Platform.environment['TOTAL_JOBS'] ?? '8') ?? 8;

  stdout.writeln(
    '[producer] enqueueing $totalJobs jobs with bursts, delays, and priorities...',
  );

  for (var i = 0; i < totalJobs; i++) {
    final delaySeconds = i >= totalJobs / 2 ? 4 : 0;
    final notBefore = delaySeconds > 0
        ? DateTime.now().add(Duration(seconds: delaySeconds))
        : null;
    final priority = i.isEven ? 9 : 2;
    final route = routing.resolve(
      RouteRequest(
        task: taskName(),
        headers: const {},
        queue: 'throttled',
      ),
    );
    final appliedPriority = route.effectivePriority(priority);

    final id = await stem.enqueue(
      taskName(),
      args: {
        'job': i + 1,
        'scheduledFor': notBefore?.toIso8601String(),
        'requestedPriority': priority,
      },
      options: TaskOptions(
        queue: 'throttled',
        priority: priority,
        maxRetries: 0,
      ),
      notBefore: notBefore,
      meta: {
        'requestedPriority': priority,
        'appliedPriority': appliedPriority,
        if (notBefore != null) 'scheduledFor': notBefore.toIso8601String(),
      },
    );

    stdout.writeln(
      '[producer] job=${i + 1} priority=$priority '
      'applied=$appliedPriority delay=${delaySeconds}s id=$id',
    );
  }

  stdout.writeln('[producer] all jobs queued. Waiting 5s before shutdown...');
  await Future<void>.delayed(const Duration(seconds: 5));

  await broker.close();
  await backend.close();
  stdout.writeln('[producer] done.');
}
