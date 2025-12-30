---
title: Dashboard
sidebar_label: Dashboard
sidebar_position: 8
slug: /core-concepts/dashboard
---

Stem ships an experimental Hotwire + Routed dashboard that surfaces live queue,
task, event, and worker data. It connects through the same broker/result-backend
contracts as your workers, so Redis, Postgres, and in-memory deployments all
work without code changes.

## Quick start (local)

1. Ensure the routed ecosystem checkout lives alongside this repo (the
   dashboard overrides `routed`, `routed_hotwire`, and related packages to
   `../routed_ecosystem` relative to `packages/dashboard`).
2. Install dependencies:

   ```bash
   dart pub get
   cd dashboard
   dart pub get
   ```

3. Start the server:

   ```bash
   dart run bin/dashboard.dart
   ```

4. Visit `http://127.0.0.1:3080/`.

## Environment variables

The dashboard reuses `StemConfig`, so it accepts the same environment settings
as workers and the CLI:

| Variable | Purpose | Default |
| --- | --- | --- |
| `STEM_BROKER_URL` | Broker URL | `redis://127.0.0.1:6379/0` |
| `STEM_RESULT_BACKEND_URL` | Result backend URL | broker URL |
| `STEM_NAMESPACE` / `STEM_DASHBOARD_NAMESPACE` | Namespace | `stem` |
| `STEM_TLS_*` | TLS configuration | unset |

Supported schemes include `redis://`, `rediss://`, `postgres://`,
`postgresql://`, and `memory://`.

## What you can do

- **Overview**: queue + worker cards and busiest queues table.
- **Tasks**: sortable queue listings, filters, row expansion, and ad-hoc enqueue.
- **Events**: live stream of queue/worker deltas over Turbo Streams.
- **Workers**: heartbeat freshness, isolate counts, queue assignments, and
  control actions (ping, soft shutdown, hard shutdown).
- **Queue recovery**: replay dead letters per queue.

## Notes

- The Events page currently synthesizes deltas from polling. Wiring Stem's
  signal bus will replace this with true lifecycle events.
- The dashboard uses the same control plane as `stem worker` (control queues +
  command replies), so the UI reflects real worker state.
