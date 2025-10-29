# Stem Dashboard Runbook

The Stem dashboard is a Hotwire + Routed application that surfaces live queue,
task, event, and worker data. It runs against the same broker/result-backend
contracts as Stem workers, so Redis, Postgres, and in-memory deployments all
behave the same way. This page explains how to run the dashboard locally, wire
the routed ecosystem overrides, and validate the control-plane features.

## Prerequisites

- Stem repository cloned (this document lives alongside the code).
- Routed ecosystem checkout at `~/code/dart_packages/routed_ecosystem`.
  - The dashboard package overrides `routed`, `routed_hotwire`,
    `server_testing`, `routed_testing`, and `property_testing` to that path.
  - A lightweight stub for `dartastic_opentelemetry_sdk` lives in
    `third_party/dartastic_opentelemetry_sdk/` so the dashboard tests keep
    working while routed completes its OpenTelemetry migration.
- A Stem-compatible broker/back-end reachable from your workstation:
  - Redis: `redis://127.0.0.1:6379/0`
  - Postgres: `postgres://user:pass@localhost:5432/stem`
  - In-memory: `memory://` (good for unit/integration tests)
- Dart SDK ≥ 3.9.2.

## Environment

Set the same environment variables used by Stem workers. The dashboard falls
back to the defaults indicated below:

| Variable | Purpose | Default |
| --- | --- | --- |
| `STEM_BROKER_URL` | Queue backend connection string | `redis://127.0.0.1:6379/0` |
| `STEM_RESULT_BACKEND_URL` | Result backend connection string | Broker URL |
| `STEM_NAMESPACE` / `STEM_DASHBOARD_NAMESPACE` | Routing namespace | `stem` |
| `STEM_TLS_*` | TLS configuration (CA/client cert, key, insecure flag) | unset |

When the broker URL uses `postgres://` or `memory://` the dashboard
automatically instantiates the appropriate adapter via `StemConfig`.

## Running the dashboard

```bash
# From the root of the Stem repository
dart pub get

cd dashboard
dart pub get
dart run bin/dashboard.dart
```

Open `http://127.0.0.1:3080/` to view the UI. Turbo keeps navigation snappy:

- **Overview** – queue + worker cards plus a busiest queues table.
- **Tasks** – sortable queue listings, filters, row expansion, and an ad-hoc
  enqueue form. Enqueued envelopes flow straight into the active broker.
- **Events** – synthetic queue/worker deltas streamed over Turbo sockets;
  wiring the real signal bus is planned.
- **Workers** – heartbeat freshness, isolate counts, and queue assignments.
  Action buttons dispatch control commands:
  - `Ping` → `ControlCommandMessage(type: 'ping')`
  - `Pause` → `ControlCommandMessage(type: 'shutdown', payload: {'mode': 'soft'})`
  - `Shutdown` → `ControlCommandMessage(type: 'shutdown', payload: {'mode': 'hard'})`
  Replies are aggregated and surfaced as flash messages.
- **Queue recovery** – per-queue DLQ replay buttons call
  `broker.replayDeadLetters`, honoring optional dry-run flags.

## Testing

The dashboard includes server, browser, and property-based tests:

```bash
cd dashboard
dart test                                       # full suite (vm + browser)
dart test test/server_test.dart                # routed + server_testing
dart test test/dashboard_browser_test.dart     # routed_testing Chromium smoke
```

`property_testing` drives `dashboard_state_property_test.dart` to ensure the
poller generates the expected delta events under random workloads.

The full suite downloads Chromium the first time it runs (via
`server_testing`). Subsequent runs reuse the cached driver and binary.

## Notes

- The temporary `dartastic_opentelemetry_sdk` stub lives under `third_party/`
  and is only used inside this repository. Once routed publishes a stable
  release the override can be removed.
- The dashboard uses `StemDashboardService` internally; swapping brokers or
  credentials simply requires updating the environment variables without code
  changes.
