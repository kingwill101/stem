import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_dlq_sandbox/shared.dart';

Future<void> main() async {
  final brokerUrl =
      Platform.environment['STEM_BROKER_URL'] ?? 'redis://localhost:6382/0';
  final backendUrl =
      Platform.environment['STEM_RESULT_BACKEND_URL'] ?? 'redis://localhost:6382/1';

  stdout.writeln('[producer] connecting broker=$brokerUrl backend=$backendUrl');

  final broker = await connectBroker(brokerUrl);
  final backend = await connectBackend(backendUrl);
  final registry = buildRegistry();
  final stem = buildStem(
    broker: broker,
    registry: registry,
    backend: backend,
  );

  final invoices = List.generate(
    int.tryParse(Platform.environment['TOTAL_INVOICES'] ?? '3') ?? 3,
    (index) => 1000 + index,
  );

  stdout.writeln('[producer] enqueueing invoices $invoices (all expected to fail first)');
  for (final invoice in invoices) {
    final id = await stem.enqueue(
      taskName(),
      args: {
        'invoiceId': invoice,
      },
      meta: {
        'createdAt': DateTime.now().toIso8601String(),
      },
      options: const TaskOptions(
        queue: 'default',
        maxRetries: 2,
      ),
    );
    stdout.writeln('[producer] queued invoice=$invoice taskId=$id');
  }

  stdout.writeln('[producer] jobs queued. Waiting 3s before exit...');
  await Future<void>.delayed(const Duration(seconds: 3));

  await broker.close();
  await backend.close();
  stdout.writeln('[producer] done.');
}
