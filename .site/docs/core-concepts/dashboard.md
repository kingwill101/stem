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
   If you do not have the routed workspace available, `dart pub get` in
   `packages/dashboard` will fail because of the local dependency overrides.
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

```dart title="lib/dashboard.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/dashboard.dart#dashboard-config

```

## Deployment & auth guidance

The dashboard does not ship with its own auth layer yet. For anything beyond
local use, place it behind your standard perimeter controls:

- **Reverse proxy + auth**: run behind Nginx/Envoy/Traefik with SSO, basic auth,
  or IP allowlists.
- **Private network**: expose the dashboard only inside a VPN/VPC.
- **TLS termination**: terminate HTTPS at the proxy and forward to
  `http://127.0.0.1:3080`.
- **Audit controls**: restrict who can issue control commands from the UI.

## Reverse proxy notes

When deploying behind a proxy, ensure the proxy forwards:

- `Host` (or set `X-Forwarded-Host`)
- `X-Forwarded-Proto` (so URLs and redirects stay correct)
- `X-Forwarded-For` (for request logging)

If you mount the dashboard at a subpath, configure the proxy to rewrite to the
app root and to pass websocket/Turbo stream upgrades.

## What you can do

- **Overview**: queue + worker cards and busiest queues table.
- **Tasks**: sortable queue listings, filters, row expansion, and ad-hoc enqueue.
- **Events**: live stream of queue/worker deltas over Turbo Streams.
- **Workers**: heartbeat freshness, isolate counts, queue assignments, and
  control actions (ping, soft shutdown, hard shutdown).
- **Queue recovery**: replay dead letters per queue.

## Required dependencies (local dev)

The dashboard depends on local `routed` ecosystem overrides:

- `routed`, `routed_hotwire`
- `server_testing`, `routed_testing`, `property_testing`
- `third_party/dartastic_opentelemetry_sdk` stub (keeps tests passing)

Make sure the `../routed_ecosystem` checkout exists relative to
`packages/dashboard` before running `dart pub get`.

## Troubleshooting: “No data”

If the UI loads but queues/workers are empty:

1. **Broker URL**: confirm `STEM_BROKER_URL` points at the broker you expect.
2. **Namespace**: verify `STEM_NAMESPACE` / `STEM_DASHBOARD_NAMESPACE` matches
   your worker namespace.
3. **Result backend**: set `STEM_RESULT_BACKEND_URL` explicitly if it differs
   from the broker (worker heartbeats live there).
4. **Redis permissions**: for Redis, the dashboard scans `stem:stream:*` and
   reads `stem:worker:heartbeat` keys. ACLs must permit `SCAN`, `XLEN`,
   `XPENDING`, `ZCARD`, and `GET` on those keys.
5. **TLS**: when using `rediss://`, make sure `STEM_TLS_*` variables are set.
6. **Workers online**: confirm workers are running and emitting heartbeats;
   if `stem worker stats --json` shows no heartbeats, the dashboard will too.

## Diagnostics

Use the CLI to confirm what the dashboard should show:

```bash
stem health \
  --broker "$STEM_BROKER_URL" \
  --backend "$STEM_RESULT_BACKEND_URL"

stem worker stats --json
stem observe queues
```

## Notes

- The Events page currently synthesizes deltas from polling. Wiring Stem's
  signal bus will replace this with true lifecycle events.
- The dashboard uses the same control plane as `stem worker` (control queues +
  command replies), so the UI reflects real worker state.
