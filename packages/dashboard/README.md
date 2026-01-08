<p align="center">
  <img src="../../.site/static/img/stem-logo.png" width="300" alt="Stem Logo" />
</p>

# Stem Dashboard Overview

This package houses the Hotwire + Routed dashboard that ships with Stem. The
server renders HTML via `routed`, streams incremental updates with Turbo, and
uses the same broker/result-backend abstractions as Stem, so Redis, Postgres,
and in-memory deployments all work without code changes. A lightweight poller
generates synthetic events (queue deltas, worker arrivals/departures) and pushes
them to the browser via Turbo Streams while we wire the full signal bus.

## Getting Started

1. Ensure the routed ecosystem checkout exists alongside this repo (the
   dependency overrides point at `../routed_ecosystem` relative to
   `packages/dashboard`). This gives us local copies of `routed`,
   `routed_hotwire`, `server_testing`, and related tooling.
2. From the repository root install dependencies for both Stem and the
   dashboard:

   ```bash
   dart pub get          # stem core workspace
   cd dashboard
   dart pub get          # dashboard package with overrides
   ```

3. Launch the dashboard server:

   ```bash
   dart run bin/dashboard.dart
   ```

4. Navigate to `http://127.0.0.1:3080/`.

Environment variables mirror the Stem CLI:

- `STEM_BROKER_URL` (defaults to `redis://127.0.0.1:6379/0`)
- `STEM_RESULT_BACKEND_URL` (defaults to the broker URL when omitted)
- `STEM_NAMESPACE` / `STEM_DASHBOARD_NAMESPACE` (defaults to `stem`)
- `STEM_TLS_*` for TLS-enabled Redis endpoints

Because the dashboard reuses `StemConfig`, any broker/result backend supported
by Stem (`redis://`, `rediss://`, `postgres://`, `postgresql://`, `memory://`)
works out of the box.

The events page keeps a websocket open to `/dash/streams` so new
queue/worker deltas appear instantly without refreshing. Tasks and workers
pages use Turbo Frames for navigation and sorting.

### Local dependency overrides

`pubspec.yaml` contains overrides pointing at the routed workspace as well as a
stub `third_party/dartastic_opentelemetry_sdk` package. The stub keeps tests
green while routed finishes its OpenTelemetry migration. When the upstream
packages are published the overrides can be removed.

### Current Features

- Overview cards with live queue/worker metrics and the busiest queues table.
- Tasks page with Turbo-driven sorting, queue filters, row expansion, and an
  ad-hoc enqueue form that publishes envelopes straight to the active broker.
- Events page fed by the dashboard poller; deltas stream to the browser in real
  time via Turbo Streams.
- Workers page showing heartbeat freshness, isolate counts, queue assignments,
  and control buttons (ping, pause/soft shutdown, hard shutdown) wired through
  Stem’s control plane.
- Queue recovery table for replaying dead letters directly from the dashboard.
- Broker/result-backend discovery using `StemConfig`, so Postgres or Redis
  deployments behave the same way.

## Runtime Data Sources

- **Queue metrics** – Redis streams are enumerated via `SCAN
  stem:stream:*`. For each queue we execute `XLEN`, `XPENDING`, and `ZCARD`
  calls across priority shards to compute pending, inflight, and delayed totals.
- **Dead letters** – `StemDashboardService` wraps `broker.replayDeadLetters`
  so the UI can replay dead letters regardless of broker implementation.
- **Worker states** – Worker heartbeats are pulled from `stem:worker:heartbeat`
  keys maintained by the result backend. The dashboard lists the latest
  heartbeat per worker and highlights stale nodes.
- **Control plane** – The control queue helpers from Stem (`ControlQueueNames`)
  power the worker controls. Ping, pause (soft shutdown), and shutdown actions
  publish control envelopes and render reply summaries in the UI.
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

These constraints guide future enhancements (enriched signal feeds, DLQ
inspection) while the current build already provides live queue/worker insight,
sortable task tables, row expansion, Turbo-streamed events, worker controls,
and DLQ replay tooling.
