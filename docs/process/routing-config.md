# Routing Configuration

Stem workers and publishers resolve queue and broadcast targets from a routing
file referenced by `STEM_ROUTING_CONFIG`. The file is parsed into a typed
`RoutingConfig`, validated by the `RoutingRegistry`, and used by helpers such as
`buildWorkerSubscription`. When no file is supplied Stem falls back to a legacy
single-queue configuration.

```yaml
default_queue:
  alias: default
  queue: primary
  fallbacks:
    - secondary
queues:
  primary:
    exchange: jobs
    routing_key: jobs.default
    priority_range: [0, 9]
  secondary: {}
broadcasts:
  control:
    delivery: at-least-once
  updates:
    delivery: at-most-once
routes:
  - match:
      task: reports.*
    target:
      type: queue
      name: primary
  - match:
      task: control.*
    target:
      type: broadcast
      name: control
```

## Queue priority ranges

- Each queue definition accepts an optional `priority_range` either as a two
  element list (`[min, max]`) or an object (`{ min: 0, max: 9 }`).
- When omitted, the queue defaults to `min: 0`, `max: 9`. Values outside the
  range trigger a `FormatException` during load.
- The routing registry clamps any priority assigned via `RoutingInfo.priority`
  or route overrides into the configured range, guaranteeing that both Redis
  and Postgres brokers store buckets within `[min, max]`.
- Publishers may continue to set `Envelope.priority`; the registry will respect
  that hint when resolving a route. When no range is defined the value is
  clamped to `[0, 9]`.

## Broadcast channels

- Add broadcast channels under `broadcasts`; each entry is keyed by the logical
  channel name and may declare:
  - `delivery`: semantic hint for consumers. `at-least-once` is the default and
    matches the behaviour of both Redis Streams and Postgres fan-out tables.
  - `durability`: optional metadata surfaced in `RoutingInfo.meta`. Current
    brokers treat it as an advisory flag.
- Routes may target broadcasts via `target: { type: broadcast, name: channel }`
  and workers subscribe by listing the channel under `STEM_WORKER_BROADCASTS`
  or via the CLI `--broadcast` flag.
- Broadcast deliveries reuse the same envelope payload; brokers set
  `RoutingInfo.broadcastChannel` to the logical channel and ensure each
  subscriber receives the message exactly once when acked.

## Loading subscriptions

- `RoutingConfigLoader` wraps filesystem loading with clearer error messages
  and is used by the CLI to show friendly diagnostics when a routing file is
  missing or malformed.
- `WorkerSubscriptionBuilder` validates queue aliases and broadcast channels
  against the loaded registry and de-duplicates selections. When no explicit
  queues are provided the builder falls back to the registry's default queue.
- The helper `buildWorkerSubscription` combines `StemConfig` defaults with
  optional overrides and is used by `stem worker multi` to honour `--queue`
  and `--broadcast`.
