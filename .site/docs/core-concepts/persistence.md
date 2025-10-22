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
