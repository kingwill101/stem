---
title: Broker Comparison
sidebar_label: Broker Overview
sidebar_position: 0
slug: /brokers
---

Stem ships with multiple broker adapters and planned integrations. Use this
reference to choose the right transport for your deployment.

| Broker            | Status         | Pros                                                    | Considerations                                             | Best For |
| ----------------- | -------------- | ------------------------------------------------------- | ---------------------------------------------------------- | -------- |
| Redis Streams     | ✅ Supported   | Single dependency, delay queues, leases via XAUTOCLAIM  | Requires Redis 7+, memory/persistence tuning               | Most production workloads |
| Postgres          | ✅ Supported   | Durable storage, transactional enqueue/dequeue, SQL ops | Slightly higher latency than Redis, requires connection pool| Workloads co-located with Postgres or requiring strict durability |
| In-memory         | ✅ Supported   | Zero setup, ideal for local dev & unit tests            | Not durable, single-process only                           | Tests, examples |
| RabbitMQ          | 🔜 Planned     | Rich routing (topics, fanout), mature ops tooling       | Requires AMQP infra, visibility via acknowledgements       | Polyglot orgs already running RabbitMQ |
| Amazon SQS        | 🔜 Planned     | Fully managed, scales automatically, global reach       | No true fanout, relies on visibility timeout semantics     | Cloud-native deployments |

### Adapter Guidance

- **Redis Streams** is the default. Enable persistence (AOF) and replicate to a
  hot standby for fault tolerance. Configure namespaces per environment with
  ACLs. The `examples/redis_postgres_worker` sample pairs Redis with Postgres
  for result storage.
- **Postgres** integrates tightly with the existing result backend for teams
  already running Postgres. Leases are implemented via advisory locks; ensure
  the connection pool matches expected concurrency.
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
