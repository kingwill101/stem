---
title: Persistence & Stores
sidebar_label: Persistence
sidebar_position: 7
slug: /core-concepts/persistence
---

Use persistence when you need durable task state, shared schedules, or
revocation storage. Stem ships with Redis and Postgres adapters and in-memory
variants for local development.

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Result backend

<Tabs>
<TabItem value="in-memory" label="In-memory (lib/bootstrap.dart)">

```dart
final backend = InMemoryResultBackend();
final stem = Stem(
  broker: InMemoryBroker(),
  registry: registry,
  backend: backend,
);
```

</TabItem>
<TabItem value="redis" label="Redis (lib/bootstrap.dart)">

```dart
final backend = await RedisResultBackend.connect('redis://localhost:6379/1');
final stem = Stem(
  broker: await RedisStreamsBroker.connect('redis://localhost:6379'),
  registry: registry,
  backend: backend,
);
```

</TabItem>
<TabItem value="postgres" label="Postgres (lib/bootstrap.dart)">

```dart
final backend = await PostgresResultBackend.connect(
  'postgres://postgres:postgres@localhost:5432/stem',
  applicationName: 'stem-app',
);
final stem = Stem(
  broker: await RedisStreamsBroker.connect('redis://localhost:6379'),
  registry: registry,
  backend: backend,
);
```

</TabItem>
</Tabs>

### Payload encoders

Result backends now respect pluggable `TaskPayloadEncoder`s. Producers encode
arguments before publishing, workers decode them once before invoking handlers,
and handler return values are encoded before they hit the backend. Every stored
status contains the encoder id (`__stemResultEncoder`), letting other processes
decode payloads without guessing formats.

Configure defaults when bootstrapping `Stem`, `StemApp`, `Canvas`, or workflow
apps:

```dart title="lib/bootstrap_encoders.dart"
import 'dart:convert';
import 'package:stem/stem.dart';

class Base64PayloadEncoder extends TaskPayloadEncoder {
  const Base64PayloadEncoder();
  @override
  Object? encode(Object? value) =>
      value is String ? base64Encode(utf8.encode(value)) : value;
  @override
  Object? decode(Object? stored) =>
      stored is String ? utf8.decode(base64Decode(stored)) : stored;
}

final app = await StemApp.inMemory(
  tasks: [...],
  argsEncoder: const JsonTaskPayloadEncoder(),
  resultEncoder: const Base64PayloadEncoder(),
  additionalEncoders: const [GzipPayloadEncoder()],
);
```

Handlers needing bespoke treatment can override `TaskMetadata.argsEncoder` and
`TaskMetadata.resultEncoder`; the worker ensures only that task uses the custom
encoder while the rest fall back to the global defaults.

## Schedule & lock stores

```dart title="lib/beat_bootstrap.dart"
final scheduleStore = await RedisScheduleStore.connect('redis://localhost:6379/2');
final lockStore = await RedisLockStore.connect('redis://localhost:6379/3');

final beat = Beat(
  broker: await RedisStreamsBroker.connect('redis://localhost:6379'),
  registry: registry,
  store: scheduleStore,
  lockStore: lockStore,
);
```

Switch to Postgres with `PostgresScheduleStore.connect` / `PostgresLockStore.connect`.

## Revoke store

Store revocations in Redis or Postgres so workers can honour `stem worker revoke`:

```bash
export STEM_REVOKE_STORE_URL=postgres://postgres:postgres@localhost:5432/stem
```

```dart
final worker = Worker(
  broker: broker,
  registry: registry,
  backend: backend,
  revokeStore: await PostgresRevokeStore.connect(
    'postgres://postgres:postgres@localhost:5432/stem',
  ),
);
```

## Tips

- In-memory adapters are great for local tests; switch to Redis/Postgres when
you need persistence or multi-process coordination.
- Postgres adapters automatically migrate required tables on first connect.
- Configure TTLs on the result backend via `backend.set` to limit retained data.
- For HA Beat deployments, use the same lock store across instances.
