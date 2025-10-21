## Overview
Celery users rely on routing primitives (named queues, routing tables, priorities, broadcast exchanges) that Stem currently lacks. Stem only copies `TaskOptions.queue` onto the envelope and workers consume a single queue. Brokers treat queue names as raw strings. To close the parity gap we introduce a first-class routing layer that:

1. Loads routing configuration (either embedded in Dart or separate YAML) describing queues, exchanges, bindings, priorities, and broadcast destinations.
2. Extends the core `Broker` contract to accept/emit routing metadata while preserving backwards compatibility (default queue when no metadata supplied).
3. Adds new broker capabilities: ordered delivery by priority, ability to bind multiple routes to a queue (for AMQP-like semantics), and broadcast fan-out delivery.
4. Updates worker/runtime plumbing so a worker can subscribe to multiple queues/broadcast channels derived from config, while coordinators can inspect and log routing decisions.

## Routing Data Model
```text
RoutingRegistry
 ├─ DefaultQueue (alias + fallbacks)
 ├─ Queues: name, exchange, routingKey, priorityRange, bindings[]
 ├─ Broadcasts: channel name, backing queue semantics per broker
 └─ Routes: matchers (task name/glob/header) → target (queue/broadcast) + overrides
```

- **Queues** represent concrete broker resources (Redis stream, Postgres table row). Each queue references an exchange (logical grouping) and default routing key.
- **Bindings** allow multiple routing keys to resolve to a queue (e.g., topic-style matching for AMQP brokers). For Redis/Postgres we’ll store the binding metadata even if implementation ignores certain fields today.
- **Routes** evaluate in order, matching on task name glob, optional headers, or explicit overrides from `Stem.enqueue`. When no route matches, we use the default queue alias.
- **Broadcasts** represent fan-out destinations. Internally we’ll model them as ephemeral queues per-worker (Redis consumer groups; Postgres dedicated table marks) but logically present a `broadcast://channel` target.

## Broker Contract Changes
Add a `RoutingEnvelope` wrapper:
```dart
class RoutingEnvelope {
  final Envelope envelope;
  final QueueRoute route; // includes queue, exchange, routingKey, priority, broadcast flag
}
```

Update `Broker.publish` signature to accept `RoutingEnvelope`. Provide a default implementation that unwraps to current behaviour (queue string) so existing brokers compile until updated. Similarly, extend `Broker.consume` with an optional list of queues and broadcast channels.

### Redis Broker
- Represent each queue as a Redis Stream per existing behaviour. For priorities, maintain a sorted set per queue that points to message IDs. When publishing with priority > 0, insert into the ZSET and move highest priority to the stream, or use multiple priority streams (`queue:p0`, `queue:p1`, …). The simpler approach is to push into the stream with priority metadata and use a Lua script during consumption to pop highest priority message; prototype in design doc.
- Broadcast channels map to Redis PUB/SUB. Each worker subscribes to `stem:broadcast:<channel>` and wraps the payload in an envelope that bypasses normal ack semantics (fire-and-forget) or uses a dedicated stream with ephemeral consumer groups. Prefer streams to guarantee delivery; create per-worker ephemeral group for each broadcast channel.

### Postgres Broker
- Add columns to `stem_jobs`: `exchange TEXT`, `routing_key TEXT`, `priority INTEGER DEFAULT 0`, `broadcast BOOLEAN DEFAULT FALSE`. Add indices on `(queue, priority DESC, created_at)` for ordering.
- For broadcast, introduce `stem_jobs_broadcast` table storing one row per broadcast message; worker fetch queries select rows where `broadcast = true` or join new table, marking rows delivered per worker.
- Update publish to populate new columns and adjust queries (SELECT ORDER BY priority DESC, created_at ASC).

## Worker Changes
- Worker constructor gains `List<String> queues` and `List<String> broadcastChannels` derived from routing config. CLI updates parse new flags (`--queue` multiple times, `--broadcast`), defaulting to config-defined values.
- Subscription: call `broker.consume` with multiple queues; each Delivery tracks originating queue/broadcast for logging.
- Broadcast handling: ensure tasks meant for broadcast replicate across all workers without interfering with normal ack flow. Provide config to flag handlers as broadcast-only.

## Configuration Loading
- Add `routing.yaml` (optional) with sections `default_queue`, `queues`, `routes`, `broadcasts`. Provide Dart `RoutingConfig` loader. If absent, behave like today (single default queue, no routes, priority=0).
- Validate config at startup, logging missing queues/broadcast targets.

## Observability & Tooling
- CLI `stem observe queues` should display queue definitions, priorities, and bindings.
- Worker heartbeat extras already include queue list; extend to include broadcast subscriptions and priority settings.
- Add metrics: per-queue priority histograms, broadcast count.

## Migration Strategy
1. Ship new broker schema guarded by feature flag; default to legacy behaviour when routing config absent.
2. Provide CLI command to generate sample `routing.yaml` mirroring existing queue usage.
3. Document fallback: if routing config is absent, `RoutingRegistry` builds default entries with the `default` queue so no behavioural change occurs.
