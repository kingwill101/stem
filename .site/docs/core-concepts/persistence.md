---
title: Persistence & Stores
sidebar_label: Persistence
sidebar_position: 7
slug: /core-concepts/persistence
---

Use persistence when you need task results, workflow state, shared schedules, or
revocation storage. Stem ships with Redis, Postgres, and SQLite adapters plus
in-memory variants for local development. The broker and result backend are
separate components: a successful enqueue does not write a task result, and a
result backend does not deliver queue work.

For the normal path, prefer `StemClient.inMemory(...)`,
`StemClient.fromUrl(...)`, or a reusable `StemStack.fromUrl(...).createClient(...)`.
Drop to `StemClient.create(...)` only when you really need custom broker or
backend factories that the adapter stack cannot express.

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Result backend

<Tabs>
<TabItem value="in-memory" label="In-memory (lib/bootstrap.dart)">

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/persistence.dart#persistence-backend-in-memory

```

</TabItem>
<TabItem value="sqlite" label="SQLite (stem_sqlite)">

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/persistence.dart#persistence-backend-sqlite

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

## Workflow store

Workflow stores persist:

- workflow runs and status
- flow step results and script checkpoint results
- suspension/watcher records
- due-run scheduling metadata

That store is what allows workflow resumes, run inspection, and recovery across
worker restarts. See the top-level [Workflows](../workflows/index.md) section
for the durable orchestration model and runtime behavior.

Each adapter owns its workflow schema or key namespace. Configure the broker,
result backend, workflow store, schedule/lock stores, and revoke store
deliberately; sharing a physical database or Redis instance does not make their
updates one transaction.

## Schedule & lock stores

```dart title="lib/beat_bootstrap.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/persistence.dart#persistence-beat-stores

```

Switch to Postgres with `PostgresScheduleStore.connect` / `PostgresLockStore.connect`.

## Revoke store

Store revocations in Redis/Postgres/SQLite so workers can honour
`stem worker revoke`:

```bash
export STEM_REVOKE_STORE_URL=postgres://postgres:postgres@localhost:5432/stem
```

```dart title="Postgres revoke store" file=<rootDir>/../packages/stem/example/docs_snippets/lib/persistence.dart#persistence-revoke-store

```

```dart title="SQLite revoke store" file=<rootDir>/../packages/stem/example/docs_snippets/lib/persistence.dart#persistence-revoke-store-sqlite

```

## Tips

- In-memory adapters are great for local tests; switch to Redis/Postgres when
you need persistence or multi-process coordination.
- SQLite is single-writer: use separate broker and backend files when practical
  to reduce contention. Sharing a file is supported, but does not provide
  multi-host coordination. For workflows, prefer a separate workflow-store file
  as well.
- SQLite is local persistence, not a mobile OS background scheduler; mobile
  platform callbacks must reopen the app and explicitly start or recover work.
- Postgres adapters run their adapter migrations on connect; migrations create
  shared `stem_*` tables, with namespace columns isolating Stem components'
  records. Coordinate migrations and permissions with the application's schema
  ownership policy.
- Configure TTLs on the result backend via `backend.set` to limit retained data.
- For HA Beat deployments, use the same lock store across instances.
