---
title: Producer API
sidebar_label: Producer API
sidebar_position: 2
slug: /core-concepts/producer
---

Enqueue tasks from your Dart services using `Stem.enqueue`. Start with the
in-memory broker, then opt into Redis/Postgres as needed.

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Enqueue tasks

<Tabs>
<TabItem value="in-memory" label="In-memory (bin/producer.dart)">

```dart
import 'package:stem/stem.dart';

Future<void> main() async {
  final registry = SimpleTaskRegistry();
  final stem = Stem(
    broker: InMemoryBroker(),
    registry: registry,
    backend: InMemoryResultBackend(),
  );

  final taskId = await stem.enqueue(
    'hello.print',
    args: {'name': 'Stem'},
  );

  print('Enqueued $taskId');
}
```

</TabItem>
<TabItem value="redis" label="Redis + Result Backend (bin/producer_redis.dart)">

```dart
import 'dart:io';
import 'package:stem/stem.dart';

Future<void> main() async {
  final brokerUrl =
      Platform.environment['STEM_BROKER_URL'] ?? 'redis://localhost:6379';

  final stem = Stem(
    broker: await RedisStreamsBroker.connect(brokerUrl),
    registry: SimpleTaskRegistry(),
    backend: await RedisResultBackend.connect('$brokerUrl/1'),
  );

  await stem.enqueue(
    'reports.generate',
    args: {'reportId': 'monthly-2025-10'},
    options: const TaskOptions(queue: 'reports', maxRetries: 3),
    meta: {'requestedBy': 'finance'},
  );
}
```

</TabItem>
<TabItem value="signed" label="Signed Payloads (bin/producer_signed.dart)">

```dart
import 'package:stem/stem.dart';

Future<void> main() async {
  final config = StemConfig.fromEnvironment();
  final stem = Stem(
    broker: await RedisStreamsBroker.connect(config.brokerUrl, tls: config.tls),
    registry: SimpleTaskRegistry(),
    backend: InMemoryResultBackend(),
    signer: PayloadSigner.maybe(config.signing),
  );

  await stem.enqueue(
    'billing.charge',
    args: {'customerId': 'cust_123', 'amount': 4200},
    notBefore: DateTime.now().add(const Duration(minutes: 5)),
  );
}
```

</TabItem>
</Tabs>

## Typed Enqueue Helpers

When you need compile-time guarantees for task arguments and result types, wrap
your handler in a `TaskDefinition`. The definition knows how to encode args and
decode results, and exposes a fluent builder for overrides (headers, meta,
options, scheduling):

```dart title="bin/producer_typed.dart"
class ReportPayload {
  const ReportPayload({required this.reportId});
  final String reportId;
}

class GenerateReportTask implements TaskHandler<String> {
  static final definition = TaskDefinition<ReportPayload, String>(
    name: 'reports.generate',
    encodeArgs: (payload) => {'reportId': payload.reportId},
    metadata: const TaskMetadata(description: 'Generate PDF reports'),
  );

  @override
  String get name => definition.name;

  @override
  TaskOptions get options => const TaskOptions(queue: 'reports');

  @override
  Future<String> call(TaskContext context, Map<String, Object?> args) async {
    final id = args['reportId'] as String;
    return await generateReport(id);
  }
}

final registry = SimpleTaskRegistry()..register(GenerateReportTask());
final stem = Stem(
  broker: InMemoryBroker(),
  registry: registry,
  backend: InMemoryResultBackend(),
);

final call = GenerateReportTask.definition.call(
  const ReportPayload(reportId: 'monthly-2025-10'),
  options: const TaskOptions(priority: 5),
  headers: const {'x-requested-by': 'analytics'},
);

final taskId = await stem.enqueueCall(call);
final result = await stem.waitForTask<String>(taskId);
```

Typed helpers are also available on `Canvas` (`definition.toSignature`) so
group/chain/chord APIs produce strongly typed `TaskResult<T>` streams.
Need to tweak headers/meta/queue at call sites? Wrap the definition in a
`TaskEnqueueBuilder` and invoke `await builder.enqueueWith(stem);`.

## Tips

- Reuse a single `Stem` instance; create it during application bootstrap.
- Capture the returned task id when you need to poll status from the result backend.
- Use `TaskOptions` to set queue, retries, priority, isolation, and visibility timeouts.
- `meta` is stored with result backend entries—great for audit trails.
- `headers` travel with the envelope and can carry tracing information.
- To schedule tasks in the future, set `notBefore`.

## Configuring Payload Encoders

Every `Stem`, `StemApp`, `StemWorkflowApp`, and `Canvas` now accepts a
`TaskPayloadEncoderRegistry` or explicit `argsEncoder`/`resultEncoder` values.
Encoders run exactly once in each direction: producers encode arguments, workers
decode them before invoking handlers, and handler return values are encoded
before hitting the result backend. Example:

```dart title="lib/bootstrap_typed_encoders.dart"
class AesPayloadEncoder extends TaskPayloadEncoder {
  const AesPayloadEncoder();
  @override
  Object? encode(Object? value) => encrypt(value);
  @override
  Object? decode(Object? stored) => decrypt(stored);
}

final app = await StemApp.inMemory(
  tasks: [...],
  argsEncoder: const AesPayloadEncoder(),
  resultEncoder: const JsonTaskPayloadEncoder(),
  additionalEncoders: const [CustomBinaryEncoder()],
);
```

Handlers needing different encoders can override `TaskMetadata.argsEncoder` and
`TaskMetadata.resultEncoder`. The worker automatically stamps every task status
with the encoder id (`__stemResultEncoder`), so downstream consumers and
adapters always know how to decode stored payloads.

Continue with the [Worker guide](../workers/programmatic-integration.md) to
consume the tasks you enqueue.
