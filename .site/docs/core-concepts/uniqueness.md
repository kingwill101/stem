---
title: Uniqueness & Deduplication
sidebar_label: Uniqueness
sidebar_position: 5
slug: /core-concepts/uniqueness
---

Stem can prevent duplicate enqueues for naturally unique tasks. Enable
`TaskOptions.unique` and configure a `UniqueTaskCoordinator` backed by a
`LockStore` (Redis or in-memory).

## Quick start

1) Mark the task as unique:

```dart title="unique_task_example.dart" file=<rootDir>/../packages/stem/example/unique_tasks/unique_task_example.dart#unique-task-options

```

2) Create a coordinator with a shared lock store:

```dart title="unique_task_example.dart" file=<rootDir>/../packages/stem/example/unique_tasks/unique_task_example.dart#unique-task-coordinator

```

3) Wire the coordinator into the producer and worker:

```dart title="unique_task_example.dart" file=<rootDir>/../packages/stem/example/unique_tasks/unique_task_example.dart#unique-task-stem-worker

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

```dart
await stem.enqueue(
  'orders.sync',
  args: {'id': 42},
  options: const TaskOptions(unique: true, uniqueFor: Duration(minutes: 10)),
  meta: {UniqueTaskMetadata.override: 'order-42'},
);
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

The `unique_tasks` example shows end-to-end behavior:

```dart title="unique_task_example.dart" file=<rootDir>/../packages/stem/example/unique_tasks/unique_task_example.dart#unique-task-enqueue

```

## Next steps

- See [Tasks & Retries](./tasks.md) for other `TaskOptions` settings.
- Combine uniqueness with [Rate Limiting](./rate-limiting.md) to guard hot paths.
