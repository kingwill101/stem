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

1. From the repository root install dependencies for both Stem and the
   dashboard:

   ```bash
   dart pub get          # stem core workspace
   cd packages/dashboard
   dart pub get          # dashboard package
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
- `DASHBOARD_BASE_PATH` (optional mount prefix such as `/dashboard`)

Because the dashboard reuses `StemConfig`, any broker/result backend supported
by Stem (`redis://`, `rediss://`, `postgres://`, `postgresql://`, `memory://`)
works out of the box.

The events page keeps a websocket open to `/dash/streams` so new
queue/worker deltas appear instantly without refreshing. Tasks and workers
pages use Turbo Frames for navigation and sorting.

## Library Embedding

`stem_dashboard` can run standalone (via `runDashboardServer`) or be mounted
into an existing `routed` engine:

```dart
import 'package:routed/routed.dart';
import 'package:stem_dashboard/dashboard.dart';

Future<void> main() async {
  final service = await StemDashboardService.connect();
  final state = DashboardState(service: service);
  await state.start();

  final engine = Engine();
  mountDashboard(
    engine: engine,
    service: service,
    state: state,
    options: const DashboardMountOptions(basePath: '/dashboard'),
  );

  await engine.serve(host: '127.0.0.1', port: 8080);
}
```

For embedded usage, the host app owns lifecycle:

- call `state.start()` before serving.
- call `state.dispose()` and `service.close()` on shutdown.

### Local dependency overrides

`pubspec.yaml` contains overrides pointing at the local Stem packages so the
dashboard always runs against the workspace versions during development. Remove
the overrides if you want to consume published packages only.

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
