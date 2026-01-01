# Ops Health Suite

This demo combines worker heartbeats, queue snapshots, and CLI health checks
so you can validate operational readiness from the command line.

## Topology

- **Redis** – broker + result backend.
- **Worker** – emits heartbeats every 5s on the `ops` queue.
- **Producer** – enqueues a small batch of tasks.

## Quick Start

```bash
cd example/ops_health_suite
# or from repo root:
# cd packages/stem/example/ops_health_suite

just deps-up
just build

# In separate terminals:
just run-worker
just run-producer

# Or use tmux:
just tmux
```

## CLI Health Checks

```bash
just build-cli

# Connectivity checks
just stem health

# Queue + worker snapshots
just stem observe queues
just stem observe workers

# Worker control plane
just stem worker ping --worker ops-worker
just stem worker stats --worker ops-worker
```

The worker heartbeats are persisted in Redis and surfaced in `stem observe
workers`. Queue depth and inflight counts appear in `stem observe queues`.
