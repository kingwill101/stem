---
title: Broker Caveats
sidebar_label: Broker Caveats
sidebar_position: 1
slug: /brokers/caveats
---

This page highlights broker-specific constraints that affect routing, priorities,
and control-plane behavior. These caveats are based on the adapter
implementations.

## Capability interfaces

The broad `Broker` contract remains the compatibility surface for existing
adapters. New integrations should expose only the optional capabilities they
actually implement:

- `QueueBroker` — publish, consume, acknowledge, negative acknowledge, and
  close.
- `LeaseBroker` — extend an active delivery lease.
- `InspectableBroker` — pending and in-flight queue counts.
- `DeadLetterBroker` — dead-letter, list, retrieve, replay, and purge dead
  letters.

`BrokerCapabilities` defaults optional behavior to `false`. Built-in adapters
explicitly declare lease extension and dead-letter support. A queue-only
adapter therefore remains valid: terminal failures are persisted in the
result backend and discarded without requeueing when no dead-letter store is
available. Built-in adapters advertise `atLeastOnce`; applications must still
make external side effects idempotent because a crash after side-effect
completion and before acknowledgement can produce a duplicate delivery.

Built-in adapters declare these interfaces in addition to `Broker`. A new
queue-only adapter can implement `QueueBroker` without implementing the
optional operations; consumers that need one can check its capability
interface or use the adapter's `BrokerCapabilities` snapshot instead of
assuming every transport has identical operational semantics. The historical
`Broker` facade supplies compatibility defaults that throw
`UnsupportedError` for operations an adapter does not support.

## Delivery and recovery matrix

The lease values below are configuration defaults. Actual recovery time also
includes the adapter's poll, claim, or sweeper interval and any broker/network
latency.

| Adapter | Lease creation | Expired-delivery recovery | Delivery guarantee |
| --- | --- | --- | --- |
| In-memory | `defaultVisibilityTimeout` | In-process claim timer (`claimInterval`) | At least once while the process is alive |
| SQLite | `defaultVisibilityTimeout` and row lock | Expiry sweeper (`sweeperInterval`) plus polling (`pollInterval`) | At least once for durable queue rows |
| Redis Streams | `defaultVisibilityTimeout` and consumer-group pending entry | `XAUTOCLAIM` on `claimInterval` | At least once while Redis data is retained |
| Postgres | `defaultVisibilityTimeout` and `locked_until` | Expiry sweeper (`sweeperInterval`) plus polling (`pollInterval`) | At least once for committed queue rows |

An automatic lease renewal is scheduled at roughly half of the remaining
lease. Short leases use that shorter interval even when the normal minimum is
one second. A renewal failure is transient from the worker's perspective:
later attempts continue, but a lease that remains expired may be delivered to
another worker. Set the visibility timeout long enough for the handler's
normal execution, terminal result handling, and broker round-trip time;
renewal starts when a delivery enters the worker and remains active through
acknowledgement. This also covers slow consume middleware and pre-execution
validation. Renewal is a safety mechanism, not a substitute for idempotent
side effects.

The worker suppresses a duplicate envelope that arrives while its original
delivery is active in that same process. A process crash, or the same task
running on different workers, remains at-least-once behavior and must be
handled with idempotent application effects.

Built-in result backends also expose `AtomicTerminalResultBackend`. Worker
terminal writes use it to ensure that a concurrent late completion cannot
replace an already persisted terminal state. This arbitration protects the
stored task result and worker-owned terminal side effects; it does not make
external HTTP calls, emails, or other application side effects exactly once.
Custom backends may omit the capability, in which case terminal persistence
uses the legacy unconditional `ResultBackend.set` path.

## In-memory broker

- **No priority buckets**: `supportsPriority` is false, so priorities are not
  enforced.
- **Single-queue consumption**: only one queue can be consumed per subscription.
- **Not durable**: data is lost when the process exits.

## SQLite broker

- **Broadcast scope is in-process**: fan-out works for subscribers running in
  the same process, but cross-process worker control broadcasts are not
  supported.
- **Single-queue consumption**: only one queue can be consumed per subscription.
- **Polling-based delivery**: tasks are polled on `pollInterval` and claimed
  via row locks; latency depends on the poll interval.
- **Single-writer constraint**: SQLite allows one writer at a time. Use
  separate broker/backend files and avoid producer writes to the backend.
- **Native assets**: build CLI bundles (`dart build cli`) when using `sqlite3`
  to ensure the native library is packaged reliably.
- **Local disk only**: avoid network filesystems for WAL-backed SQLite files.

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
  worker dies or stops renewing its lease, jobs become visible again after the
  lease expires.
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
- **Long-running tasks** should emit heartbeats for liveness and rely on the
  worker's automatic renewal or call `context.extendLease(...)` when they need
  explicit lease time. A heartbeat alone does not extend the broker lease.
- **Renewal failures** are exposed through `stem.lease.renewal_failed` and
  structured worker logs. Renewal attempts continue after a transient failure;
  a lease that remains lost can still produce an at-least-once redelivery.

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

```dart title="brokers.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/brokers.dart#brokers-sqlite

```
