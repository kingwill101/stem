---
title: Routing Configuration
sidebar_label: Routing
sidebar_position: 3
slug: /core-concepts/routing
---

Stem workers and publishers resolve queue and broadcast targets from the routing
file referenced by `STEM_ROUTING_CONFIG`. The file is parsed into a typed
`RoutingConfig`, validated by the `RoutingRegistry`, and used by helpers such as
`buildWorkerSubscription`. When no file is supplied Stem falls back to a legacy
single-queue configuration.

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

<Tabs>
<TabItem value="yaml" label="config/routing.yaml">

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

</TabItem>
<TabItem value="dart" label="lib/routing.dart">

```dart
import 'package:stem/stem.dart';

Future<RoutingRegistry> loadRouting() async {
  final config = await RoutingConfigLoader().loadFromYamlFile(
    'config/routing.yaml',
  );
  return RoutingRegistry(config);
}

final registry = RoutingRegistry(
  RoutingConfig(
    defaultQueue: DefaultQueue(alias: 'default', queue: 'primary'),
    queues: {'primary': QueueSpec()},
    routes: [
      RouteSpec(match: RouteMatch(task: 'reports.*'), target: QueueTarget('primary')),
    ],
  ),
);
```

</TabItem>
</Tabs>

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

## Using the config in Dart

Load the routing file once during service start-up and reuse the registry across
producers and workers:

```dart title="lib/routing.dart"
import 'package:stem/stem.dart';

Future<(Stem, Worker)> bootstrapStem() async {
  final routing = await RoutingConfigLoader().loadFromYamlFile(
    'config/routing.yaml',
  );
  final registry = SimpleTaskRegistry()..register(EmailTask());

  final stem = Stem(
    broker: await RedisStreamsBroker.connect('redis://localhost:6379'),
    registry: registry,
    backend: InMemoryResultBackend(),
    routing: RoutingRegistry(routing),
  );

  final worker = Worker(
    broker: await RedisStreamsBroker.connect('redis://localhost:6379'),
    registry: registry,
    backend: InMemoryResultBackend(),
    routing: RoutingRegistry(routing),
    subscription: buildWorkerSubscription(
      config: StemConfig.fromEnvironment(),
      registry: RoutingRegistry(routing),
    ),
  );

  return (stem, worker);
}
```

For lightweight services or tests, you can construct the registry inline:

```dart
final registry = RoutingRegistry(
  RoutingConfig(
    defaultQueue: DefaultQueue(alias: 'default', queue: 'primary'),
    queues: {'primary': QueueSpec()},
    routes: [
      RouteSpec(match: RouteMatch(task: 'reports.*'), target: QueueTarget('primary')),
    ],
  ),
);
```

Both approaches keep routing logic declarative while letting you evolve queue
topology without editing code.
