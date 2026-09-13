---
title: Choosing a Backend
sidebar_label: Choosing a backend
sidebar_position: 4
slug: /getting-started/choosing-a-backend
---

Stem separates delivery from stored state:

| Situation | Broker | Store |
| --- | --- | --- |
| Tests and demos | In-memory | In-memory |
| Shared queue | Redis | Redis or Postgres |
| SQL visibility | Postgres | Postgres |
| Embedded service | SQLite | SQLite |

In-memory state is process-local and not restart-durable. A persistent store
does not make effects exactly once; handlers still need idempotency. See
[Persistence](../core-concepts/persistence.md) and
[Broker Overview](../brokers/overview.md). Check the package version your
application resolves before copying adapter setup: source checkouts and pub
releases may expose different APIs.
