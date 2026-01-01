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

## Postgres broker

- **Single-queue consumption**: only one queue can be consumed per subscription.
- **Polling-based delivery**: workers poll for due jobs on an interval.
- **Dead letter retention**: dead letters are retained for a default window
  (7 days) unless configured otherwise.
- **Broadcast channels**: broadcasts are stored in a separate table and read
  alongside queue deliveries.

## Tips

- Use routing subscriptions to pin workers to a single queue when using Redis
  or Postgres.
- Prefer Redis when you need low-latency delivery and high throughput.
- Prefer Postgres when you need SQL visibility and a single durable store.
