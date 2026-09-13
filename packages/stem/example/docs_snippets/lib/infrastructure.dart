// Copyright (c) 2025 Glenford Williams <hey@glenfordwilliams.com>
// SPDX-License-Identifier: MIT

// #region infrastructure-main
import 'dart:io';

import 'package:stem/stable.dart';
import 'package:stem_redis/stem_redis.dart';

/// Shared task contract used by producers and workers.
final doubleTask = TaskDefinition<int, int>(
  name: 'infrastructure.double',
  encodeArgs: (value) => {'value': value},
  decodeArgs: (args) => args['value']! as int,
);

Future<void> main(List<String> args) async {
  if (args.isEmpty ||
      !const ['enqueue', 'work', 'result'].contains(args.first) ||
      (args.first == 'result' ? args.length != 2 : args.length != 1)) {
    stderr.writeln('Usage: infrastructure.dart enqueue | work | result <id>');
    exitCode = 64;
    return;
  }
  final brokerUrl = Platform.environment['STEM_BROKER_URL'];
  final backendUrl = Platform.environment['STEM_RESULT_BACKEND_URL'];
  if (brokerUrl == null || backendUrl == null) {
    stderr.writeln('Set STEM_BROKER_URL and STEM_RESULT_BACKEND_URL.');
    exitCode = 64;
    return;
  }

  final client = await StemClient.fromUrl(
    brokerUrl,
    adapters: [
      StemRedisAdapter(
        namespace:
            Platform.environment['STEM_NAMESPACE'] ?? 'infrastructure-demo',
      ),
    ],
    overrides: StemStoreOverrides(backend: backendUrl),
    tasks: [
      doubleTask.handler(entrypoint: (context, value) async => value * 2),
    ],
  );
  try {
    switch (args.first) {
      case 'enqueue':
        final id = await client.enqueueCall(doubleTask.buildCall(21));
        stdout.writeln(id); // Retain this ID for a separate result observer.
      case 'work':
        final worker = await client.createWorker();
        // A one-shot worker: no start() call before runUntilIdle().
        final outcome = await worker.runUntilIdle(
          budget: const Duration(seconds: 45),
          idleTimeout: const Duration(seconds: 2),
        );
        stdout.writeln('Worker stopped: ${outcome.reason.name}');
        if (outcome.reason == WorkerRunStopReason.failed) exitCode = 1;
      case 'result':
        final result = await doubleTask.waitFor(
          client,
          args[1],
          timeout: const Duration(seconds: 10),
        );
        if (result == null) {
          stderr.writeln(
            'No result in this observation window; check the worker.',
          );
          exitCode = 1;
        } else {
          stdout.writeln(result.value); // 42
        }
    }
  } finally {
    await client.close();
  }
}
// #endregion infrastructure-main
