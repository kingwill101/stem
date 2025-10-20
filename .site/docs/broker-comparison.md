---
id: broker-comparison
title: Broker Comparison
sidebar_label: Broker Comparison
---

Stem ships with multiple broker adapters and planned integrations. Use this
reference to choose the right transport for your deployment.

| Broker            | Status         | Pros                                                    | Considerations                                             | Best For |
| ----------------- | -------------- | ------------------------------------------------------- | ---------------------------------------------------------- | -------- |
| Redis Streams     | ✅ Supported   | Single dependency, delay queues, leases via XAUTOCLAIM  | Requires Redis 7+, keep an eye on memory & persistence     | Most production workloads |
| In-memory         | ✅ Supported   | Zero setup, ideal for local dev & unit tests            | Not durable, single-process only                           | Tests, examples |
| RabbitMQ          | 🔜 Planned     | Rich routing (topics, fanout), mature ops tooling       | Requires AMQP infra, visibility via acknowledgements       | Polyglot orgs already running RabbitMQ |
| Amazon SQS        | 🔜 Planned     | Fully managed, scales automatically, global reach       | No true fanout, relies on visibility timeout semantics     | Cloud-native deployments |

### Adapter Guidance

- **Redis Streams** is the default. Enable persistence (AOF) and replicate to a
  hot standby for fault tolerance. Configure namespaces per environment with
  ACLs.
- **In-memory** adapters mirror the Redis API and are safe for smoke tests.
- **RabbitMQ & SQS** bindings follow the same `Broker` contract. Keep tasks
  idempotent—visibility/lease guarantees differ slightly (documented in the
  adapter guides once released).

### Selecting a Broker

1. Start with Redis Streams unless your platform mandates a specific broker.
2. Use in-memory during development to simplify onboarding.
3. If you already operate RabbitMQ/SQS at scale, wire the respective adapter
   and monitor the lease/ack semantics described in the spec.
