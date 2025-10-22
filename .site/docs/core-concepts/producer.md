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

## Tips

- Reuse a single `Stem` instance; create it during application bootstrap.
- Capture the returned task id when you need to poll status from the result backend.
- Use `TaskOptions` to set queue, retries, priority, isolation, and visibility timeouts.
- `meta` is stored with result backend entries—great for audit trails.
- `headers` travel with the envelope and can carry tracing information.
- To schedule tasks in the future, set `notBefore`.

Continue with the [Worker guide](../workers/programmatic-integration.md) to
consume the tasks you enqueue.
