---
title: Broker Comparison
sidebar_label: Broker Overview
sidebar_position: 0
slug: /brokers
---

Stem ships with multiple broker adapters and planned integrations. This page
explains what a broker does, how it differs from result storage, and how to
choose the right transport for your deployment.

## What is a broker?

A **broker** is the message transport between producers and workers. When you
call `Stem.enqueue`, the broker persists the task envelope and makes it
available to one or more workers. The broker is not where results live; it only
handles delivery.

In Stem:

- **Producer → Broker**: publishes a task envelope.
- **Worker ← Broker**: consumes and acknowledges deliveries.
- **Result backend**: stores the task result/state (separate component).

## Broker vs result backend

Use the broker for **delivery**, and a result backend for **history**:

- **Broker**: queues, leases, priority, delayed delivery, broadcast channels.
- **Result backend**: task status, result payloads, heartbeats, group/chord
  metadata.

You can mix and match (e.g. Redis broker + Postgres backend) depending on
durability and performance needs.

## What a Stem broker must provide

Every broker adapter implements the same `Broker` contract and should support:

- **At-least-once delivery** with acknowledgements.
- **Visibility/leases** so workers can extend or retry tasks safely.
- **Priority buckets** so higher-priority tasks are dispatched first.
- **Delayed tasks** via `notBefore` and retry scheduling.
- **Broadcast channels** (used for worker control commands).

If the broker does not support a feature, it should document the limitation.
Planned adapters may not support full control-plane tooling until release.

## Broker feature matrix

| Broker            | Status       | Delivery | Delays | Priority | Broadcast/Control | Notes |
| ----------------- | ------------ | -------- | ------ | -------- | ----------------- | ----- |
| Redis Streams     | ✅ Supported | At-least-once | ✅ | ✅ | ✅ | Lowest latency, great default. |
| Postgres          | ✅ Supported | At-least-once | ✅ | ✅ | ✅ | Durable, SQL-friendly; higher latency than Redis. |
| SQLite            | ✅ Supported | At-least-once | ✅ | ✅ | ⚠️ | Single-host file broker; broadcast fan-out is in-process only. |
| In-memory         | ✅ Supported | At-least-once | ✅ | ✅ | ✅ | Single-process only; testing/dev. |
| RabbitMQ          | 🔜 Planned   | AMQP acks | ✅ | ✅ | ✅ | Mature routing; requires AMQP infra. |
| Amazon SQS        | 🔜 Planned   | Visibility timeout | ✅ | Limited | ⚠️ | Fully managed; no native fanout. |

## Broker summaries

### Redis Streams

Best default for most deployments: low latency, strong support for delayed
tasks and leases, and mature operations tooling. Tune persistence (AOF or RDB)
based on durability needs.

### Postgres

A good fit when you prefer a single database dependency or want SQL visibility
into queue state. Slightly higher latency than Redis; use a connection pool
aligned with worker concurrency.

### SQLite

Best for single-host development and demos. The SQLite broker uses polling-
based delivery and supports broadcast fan-out only for subscribers in the same
process. Use separate SQLite files for broker vs. backend to avoid WAL
contention. See the [SQLite adapter guide](./sqlite.md) for setup and
operational notes.

### In-memory

Perfect for tests and local demos. Not durable and only works inside a single
process.

### RabbitMQ (planned)

Ideal for teams already invested in AMQP routing and tooling. Stem will map its
queue/broadcast model onto topic and fanout exchanges.

### Amazon SQS (planned)

Great for managed AWS deployments and automatic scaling. Expect higher latency
and limited fanout without SNS.

### Adapter Guidance

- **Redis Streams** is the default. Enable persistence (AOF) and replicate to a
  hot standby for fault tolerance. Configure namespaces per environment with
  ACLs. The `packages/stem/example/redis_postgres_worker` sample pairs Redis
  with Postgres for result storage.
- **Postgres** integrates tightly with the existing result backend for teams
  already running Postgres. Delivery leases are tracked in queue rows (for
  example via `locked_until`), so ensure the connection pool matches expected
  concurrency.
- **SQLite** is ideal for single-host development and demos. Use separate DB
  files for broker and backend; avoid producer writes to the backend.
- **In-memory** adapters mirror the Redis API and are safe for smoke tests.
- **RabbitMQ & SQS** bindings follow the same `Broker` contract. Keep tasks
  idempotent—visibility/lease guarantees differ slightly (documented in the
  adapter guides once released).

### Selecting a Broker

1. Start with Redis Streams unless your platform mandates a specific broker.
2. Consider Postgres when you need transactional enqueue/dequeue or prefer a
   single database dependency with built-in durability.
3. Use in-memory during development to simplify onboarding.
4. If you already operate RabbitMQ/SQS at scale, wire the respective adapter
   and monitor the lease/ack semantics described in the spec.

## Broker configuration quick start

Set the broker URL:

```bash
export STEM_BROKER_URL=redis://localhost:6379
```

Then bootstrap (pass a namespace if you want logical separation per env):

```dart
final broker = await RedisStreamsBroker.connect(
  Platform.environment['STEM_BROKER_URL']!,
  namespace: 'stem',
);
```

Or use the broker snippet entrypoints:

```dart title="brokers.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/brokers.dart#brokers-redis

```

```dart title="brokers.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/brokers.dart#brokers-postgres

```

```dart title="brokers.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/brokers.dart#brokers-sqlite

```

```dart title="brokers.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/brokers.dart#brokers-in-memory

```

For result storage, see the [Persistence](../core-concepts/persistence.md)
guide.

Need adapter limitations and behavior details? See
[Broker Caveats](./caveats.md).
