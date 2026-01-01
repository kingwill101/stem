---
title: Uniqueness & Deduplication
sidebar_label: Uniqueness
sidebar_position: 5
slug: /core-concepts/uniqueness
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

Stem can prevent duplicate enqueues for naturally unique tasks. Enable
`TaskOptions.unique` and configure a `UniqueTaskCoordinator` backed by a
`LockStore` (Redis or in-memory).

## Quick start

1) Mark the task as unique:

```dart title="lib/uniqueness.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/uniqueness.dart#uniqueness-task-options

```

2) Create a coordinator with a shared lock store:

<Tabs>
<TabItem value="in-memory" label="In-memory (local)">

```dart title="lib/uniqueness.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/uniqueness.dart#uniqueness-coordinator-inmemory

```

</TabItem>
<TabItem value="redis" label="Redis (shared)">

```dart title="lib/uniqueness.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/uniqueness.dart#uniqueness-coordinator-redis

```

</TabItem>
</Tabs>

3) Wire the coordinator into the producer and worker:

```dart title="lib/uniqueness.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/uniqueness.dart#uniqueness-stem-worker

```

## How uniqueness works

- The unique key is derived from task name, queue, args, headers, and meta
  (excluding keys prefixed with `stem.`).
- Keys are canonicalized (sorted maps, stable JSON) to ensure equivalent inputs
  hash to the same key.
- Use `uniqueFor` to control the lock TTL. When unset, Stem falls back to the
  task `visibilityTimeout`, envelope visibility timeout, or the coordinator
  default TTL (in that order).

## Override the unique key

Override the computed key when you need custom grouping:

```dart title="lib/uniqueness.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/uniqueness.dart#uniqueness-override-key

```

## What happens on duplicates

- Duplicate enqueues return the existing task id.
- The `stem.tasks.deduplicated` metric increments.
- Duplicates are recorded on the task status metadata under
  `stem.unique.duplicates`.

## Release semantics

Unique locks are released after task completion (success or failure) by the
worker that holds the lock. If a worker crashes mid-task, the lock expires when
the TTL elapses, allowing a future enqueue.

## Retry behavior

Retries keep the original task id. Uniqueness is evaluated at enqueue time, so
retries do not create new unique claims.

## Example

The snippet below shows the enqueue behavior (see `unique_tasks` for a full demo):

```dart title="lib/uniqueness.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/uniqueness.dart#uniqueness-enqueue

```

## Next steps

- See [Tasks & Retries](./tasks.md) for other `TaskOptions` settings.
- Combine uniqueness with [Rate Limiting](./rate-limiting.md) to guard hot paths.
