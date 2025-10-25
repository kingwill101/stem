# Stem Dashboard Overview

This package houses the Hotwire + Routed dashboard that ships with Stem. The
server renders HTML via `routed`, streams incremental updates with Turbo, and
talks to Redis directly for queue and worker insights. A lightweight poller
generates synthetic events (queue deltas, worker arrivals/departures) and pushes
them to the browser via Turbo Streams.

## Getting Started

```bash
cd dashboard
dart pub get
dart run bin/dashboard.dart
```

Environment variables mirror the Stem CLI:

- `STEM_BROKER_URL` (defaults to `redis://127.0.0.1:6379/0`)
- `STEM_RESULT_BACKEND_URL` (defaults to the broker URL when omitted)
- `STEM_NAMESPACE` / `STEM_DASHBOARD_NAMESPACE` (defaults to `stem`)
- `STEM_TLS_*` for TLS-enabled Redis endpoints

Open `http://127.0.0.1:3080/` after the server starts. The events page keeps a
websocket open to `/dash/streams` so new queue/worker deltas appear instantly
without refreshing. Tasks and workers pages use Turbo Frames for navigation and
sorting.

### Current Features

- Overview cards with live queue/worker metrics and the busiest queues table.
- Tasks page with Turbo-driven sorting, queue filters, row expansion, and an
  ad-hoc enqueue form that publishes envelopes straight to Redis.
- Events page fed by the dashboard poller; deltas stream to the browser in real
  time via Turbo Streams.
- Workers page showing heartbeat freshness, isolate counts, and queue
  assignments.

## Runtime Data Sources

- **Queue metrics** – Redis streams are enumerated via `SCAN
  stem:stream:*`. For each queue we execute `XLEN`, `XPENDING`, and `ZCARD`
  calls across priority shards to compute pending, inflight, and delayed totals.
- **Dead letters** – The Redis `stem:dead:<queue>` lists expose DLQ counts
  (used for dashboard summaries). Replay/inspect controls will call the same
  `replayDeadLetters`/`purgeDeadLetters` APIs exposed by Stem.
- **Worker states** – Worker heartbeats are pulled from `stem:worker:heartbeat`
  keys maintained by the result backend. The dashboard lists the latest
  heartbeat per worker and highlights stale nodes.
- **Control plane** – The control queue helpers from Stem (`ControlQueueNames`)
  are mirrored so the dashboard can publish worker commands (pause, ping,
  shutdown) and await replies. Actions are wired once the UI surfaces control
  buttons.
- **Ad-hoc enqueue** – Enqueue forms publish envelopes directly to Redis using
  the same stream schema as Stem. Because the dashboard does not know the task
  registry, operators will provide task name + payload manually.

## Observability Gaps

- **Event fidelity** – The current implementation synthesizes events from queue
  and worker deltas. Wiring Stem’s signal bus into Redis (or pushing OTLP
  events) will replace the synthetic feed with true task lifecycle events.
- **Queue discovery without config** – If deployments create queues on the fly,
  the SCAN fallback keeps the dashboard usable, but an explicit allowlist from
  routing config would avoid surprises.
- **Task catalog** – Stem does not expose a registry enumeration API. The
  dashboard will keep offering raw task name/argument forms until such an API
  exists or operators provide metadata via configuration.

These constraints guide future enhancements (control actions, DLQ replays,
signal bridges) while the current build already provides live queue/worker
insight, sortable task tables, row expansion, and Turbo-streamed events.
