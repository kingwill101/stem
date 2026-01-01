## Overview
Complete routing parity requires implementing the remaining behaviors that Celery users expect (priority preemption, broadcast fan-out, multi-queue workers). The work splits into three major surfaces plus tooling:

1. **Broker enhancements** for Redis and Postgres to respect `RoutingInfo.priority` and broadcast metadata.
2. **Worker/CLI updates** to honour multi-queue/broadcast subscriptions and expose routing state via heartbeats & commands.
3. **Tooling + migration support** so operators can adopt the richer routing config safely (schema migrations, config loaders, documentation).

## Priority Delivery
- **Config**: Extend `QueueDefinition.priorityRange` to accept both list `[min, max]` and object forms; default to `[0, 0]`. Validation ensures `min <= max`. Routing registry normalises decisions to clamp published priority within range.
- **Redis Streams**:
  - Use N discrete streams per priority bucket (e.g. `queue:p0`…`queue:p9`) with publish selecting bucket via priority.
  - Consumer loop fetches buckets in descending order until it finds data; reuses existing `_ensureGroup`.
  - Supports configurable max priority per queue (default 9).
- **Postgres**:
  - Migration adds `priority INT DEFAULT 0`, index on `(queue, priority DESC, created_at)`.
  - `_reserve` query orders by priority/created_at and writes new priority on publish.
- **Testing**: Unit tests for queue normalisation + integration tests verifying higher priority tasks preempt lower ones.

## Broadcast Fan-out
- **Config**: `BroadcastDefinition` gains `delivery` (`at-least-once` default) and optional `durability`.
- **RoutingInfo**: `RoutingInfo.broadcast` carries `delivery` meta for broker-specific logic.
- **Redis**:
  - Represent broadcasts as streams (`stem:broadcast:<channel>`).
  - Each worker consumer group named after worker ID; publish writes to stream with broadcast metadata.
  - Worker ack removes entry for that worker; stream trimmed periodically.
- **Postgres**:
  - New `stem_broadcast_jobs` table keyed by message ID + worker ID with delivery tracking.
  - Publish writes to base table + broadcast table; consume union of personal queue + broadcast.
- **Testing**: Integration scenarios ensuring that N workers receive each broadcast once, tolerant to worker restarts.

## Worker & CLI Subscriptions
- **Worker runtime**:
  - `Worker` constructor accepts `RoutingSubscription` (queues + broadcast channels).
  - `broker.consume` passes subscription, enabling multi-queue/broadcast.
  - Heartbeat extends payload with `queues` (list) and `broadcasts`.
- **CLI/Config**:
  - Update CLI flags: `--queue` repeatable, `--broadcast` repeatable; absence triggers registry defaults.
  - `stem worker multi` updates env templates/docstrings accordingly.
- **Observability**: Heartbeat output & CLI stats show multi-queue info, aggregated metrics keyed by queue/broadcast.

## Tooling & Migration
- **Routing Config Loader**: Helper reads file path from `StemConfig.routingConfigPath`, falls back to legacy config, and provides friendly errors. CLI uses same loader to ensure consistent view.
- **Sample Generator**: Optional CLI command `stem routing dump` to emit current config skeleton (queues, broadcasts, routes).
- **Documentation**: Update README/docs with new config structure, CLI flags, and migration steps.
- **Postgres Migration Plan**: Document rolling strategy (add columns nullable, backfill, flip ordering, drop fallback).

## Validation
- Update integration suites to cover routing scenarios (priority, broadcast, multi-queue workers).
- Run `openspec validate complete-routing-parity --strict` before implementation completion.
