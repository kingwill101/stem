# Routing Parity Demo

This example exercises Stem's routing parity features—queue priorities,
broadcast fan-out, and multi-queue workers—using only Redis Streams and the
built-in in-memory result backend. All routing configuration is embedded in
code so you can run it without creating additional config files.

## Quick start

```bash
cd examples/routing_parity
dart pub get
docker compose up -d
```

Open two terminals:

1. **Worker** – consumes `standard` and `critical` queues plus the `ops`
   broadcast channel, logging the queue, priority, and subject of each task.

   ```bash
   dart run bin/worker.dart
   ```

2. **Publisher** – enqueues a mix of invoices, high/low-priority reports, and an
   ops broadcast. The worker shows that the higher-priority report preempts the
   lower-priority one and that both workers receive the broadcast once.

   ```bash
   dart run bin/publisher.dart
   ```

Redis defaults to `redis://localhost:6379`. Override the connection with
`ROUTING_DEMO_REDIS_URL` if needed.

When you are done, stop the worker and bring down Redis:

```bash
docker compose down
```

## What it covers

- **Priority clamping** – The routing config defines a `critical` queue with a
  `[3, 9]` priority range. Even when the publisher enqueues a `priority: 1`
  report, the routing registry clamps it to `3`, so the higher-priority report
  is delivered first.
- **Broadcast fan-out** – Tasks routed to `ops` use broadcast semantics, so every
  subscribed worker receives the message once and acknowledges it independently.
- **Multi-queue subscriptions** – The worker listens to both `standard` and
  `critical` queues along with the `ops` broadcast channel via a single
  `RoutingSubscription`.

Inspect `lib/routing_demo.dart` to see the embedded routing configuration and
task handlers that power the demo.

### Local build + Docker deps (just)

```bash
just deps-up
just build
# In separate terminals:
just run-worker
just run-publisher
# Or:
just tmux
```
