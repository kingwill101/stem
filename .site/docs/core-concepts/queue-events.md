---
title: Queue Events
sidebar_label: Queue Events
sidebar_position: 9
slug: /core-concepts/queue-events
---

Stem supports queue-scoped custom events similar to BullMQ `QueueEvents` and
"custom events" patterns.

Use this when you need lightweight event streams for domain notifications
(`order.created`, `invoice.settled`) without creating task handlers.

## API Surface

- `QueueEventsProducer.emit(queue, eventName, payload, headers, meta)`
- `QueueEventsProducer.emitJson(queue, eventName, dto, headers, meta)`
- `QueueEventsProducer.emitVersionedJson(queue, eventName, dto, version, headers, meta)`
- `QueueEvents.start()` / `QueueEvents.close()`
- `QueueEvents.events` stream (all events for that queue)
- `QueueEvents.on(eventName)` stream (filtered by name)

All events are delivered as `QueueCustomEvent`, which implements `StemEvent`.
Use `event.payloadValue(...)` / `event.requiredPayloadValue(...)` to read typed
payload fields instead of repeating raw `payload['key']` casts.
If one queue event maps to one DTO, use `event.payloadJson(...)` or
`event.payloadAs(codec: ...)` to decode the whole payload in one step.

## Producer + Listener

```dart title="lib/queue_events.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/queue_events.dart#queue-events-producer-listener

```

## Fan-out to Multiple Listeners

Multiple listeners on the same queue receive each emitted event.

```dart title="lib/queue_events.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/queue_events.dart#queue-events-fanout

```

## Semantics

- Events are queue-scoped: listeners receive only events for their configured
  queue.
- `emitJson(...)` is the DTO convenience path when the payload already exposes
  `toJson()`.
- `emitVersionedJson(...)` is the same convenience path when the payload
  schema should persist an explicit `__stemPayloadVersion`.
- `on(eventName)` matches exact event names.
- `headers` and `meta` round-trip to listeners.
- Event names and queue names must be non-empty.
- Delivery follows the underlying broker's broadcast behavior for active
  listeners (no historical replay API is built into `QueueEvents`).

## When to Use Queue Events vs Signals

- Use [Signals](./signals.md) for runtime lifecycle hooks (task/worker/scheduler/control).
- Use Queue Events for application-domain events you publish and consume.
