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

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/persistence.dart#persistence-backend-in-memory

```

</TabItem>
<TabItem value="redis" label="Redis (lib/bootstrap.dart)">

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/persistence.dart#persistence-backend-redis

```

</TabItem>
<TabItem value="postgres" label="Postgres (lib/bootstrap.dart)">

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/persistence.dart#persistence-backend-postgres

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

```dart title="lib/bootstrap_encoders.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/persistence.dart#persistence-encoders

```

Handlers needing bespoke treatment can override `TaskMetadata.argsEncoder` and
`TaskMetadata.resultEncoder`; the worker ensures only that task uses the custom
encoder while the rest fall back to the global defaults.

## Schedule & lock stores

```dart title="lib/beat_bootstrap.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/persistence.dart#persistence-beat-stores

```

Switch to Postgres with `PostgresScheduleStore.connect` / `PostgresLockStore.connect`.

## Revoke store

Store revocations in Redis or Postgres so workers can honour `stem worker revoke`:

```bash
export STEM_REVOKE_STORE_URL=postgres://postgres:postgres@localhost:5432/stem
```

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/persistence.dart#persistence-revoke-store

```

## Tips

- In-memory adapters are great for local tests; switch to Redis/Postgres when
you need persistence or multi-process coordination.
- Postgres adapters automatically migrate required tables on first connect.
- Configure TTLs on the result backend via `backend.set` to limit retained data.
- For HA Beat deployments, use the same lock store across instances.
