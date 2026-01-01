---
title: Broker Caveats
sidebar_label: Broker Caveats
sidebar_position: 1
slug: /brokers/caveats
---

This page highlights broker-specific constraints that affect routing, priorities,
and control-plane behavior. These caveats are based on the adapter
implementations.

## In-memory broker

- **No priority buckets**: `supportsPriority` is false, so priorities are not
  enforced.
- **No broadcast channels**: broadcast routing and subscriptions are rejected.
- **Single-queue consumption**: only one queue can be consumed per subscription.
- **Not durable**: data is lost when the process exits.

## Redis Streams broker

- **Single-queue consumption**: only one queue can be consumed per subscription.
- **Priority uses per-queue streams**: each priority bucket maps to a dedicated
  stream key.
- **Delayed delivery**: delayed tasks are stored in a sorted set and re-enqueued
  when due.
- **Broadcast channels**: broadcasts are stored in per-channel streams and
  consumed via dedicated consumer groups.
- **Visibility timeouts**: the broker reclaims idle deliveries via
  `XAUTOCLAIM`. Extending a lease requeues the task into the delayed set
  (it does not update the original stream entry).
- **Key eviction risk**: Redis eviction policies can drop stream, delayed, or
  dead-letter keys. Use a maxmemory policy that avoids evicting Stem keys, or
  isolate Stem data in a dedicated Redis instance.

## Postgres broker

- **Single-queue consumption**: only one queue can be consumed per subscription.
- **Polling-based delivery**: workers poll for due jobs on an interval.
- **Visibility timeouts**: tasks are locked with a `locked_until` lease; if a
  worker dies or stops heartbeating, jobs become visible again after the lease
  expires.
- **Dead letter retention**: dead letters are retained for a default window
  (7 days) unless configured otherwise.
- **Broadcast channels**: broadcasts are stored in a separate table and read
  alongside queue deliveries.

## Result backend caveat (ordering)

- **Group result ordering**: group/chord results are stored as maps
  (Redis hashes / Postgres tables) and returned without ordering guarantees.
  If you need stable ordering, sort results by task id or track ordering in
  group metadata.

## Shutdown semantics (broker impact)

- **Soft shutdowns are cooperative**: brokers only see acknowledgements (or
  requeues). If a worker stops without acking a delivery, the task becomes
  visible again after the visibility lease expires (Redis reclaim interval /
  Postgres `locked_until`).
- **Long-running tasks** should emit heartbeats or extend leases so the broker
  does not re-deliver them mid-execution.

## Tips

- Use routing subscriptions to pin workers to a single queue when using Redis
  or Postgres.
- Prefer Redis when you need low-latency delivery and high throughput.
- Prefer Postgres when you need SQL visibility and a single durable store.

## Example entrypoints

```dart title="brokers.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/brokers.dart#brokers-in-memory

```

```dart title="brokers.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/brokers.dart#brokers-redis

```

```dart title="brokers.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/brokers.dart#brokers-postgres

```
