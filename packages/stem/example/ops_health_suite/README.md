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

task deps-up
task build

# In separate terminals:
task run-worker
task run-producer

# Or use tmux:
task tmux
```

## CLI Health Checks

```bash
task build-cli

# Connectivity checks
task stem health

# Queue + worker snapshots
task stem observe queues
task stem observe workers

# Worker control plane
task stem worker ping --worker ops-worker
task stem worker stats --worker ops-worker
```

The worker heartbeats are persisted in Redis and surfaced in `stem observe
workers`. Queue depth and inflight counts appear in `stem observe queues`.
