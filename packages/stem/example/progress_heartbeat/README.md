# Progress + Heartbeat Demo

This example shows how to publish task progress updates and heartbeats, and how
operators can observe worker heartbeats via the CLI. The worker logs progress
and heartbeat events emitted from the in-process event stream.

## Topology

- **Redis** – broker and result backend.
- **Worker** – runs `progress.demo`, emits heartbeats + progress updates, and
  logs them via `worker.events`.
- **Producer** – enqueues a long-running progress task.

## Quick Start (Docker Compose)

```bash
cd example/progress_heartbeat
# or from repo root:
# cd packages/stem/example/progress_heartbeat

docker compose up --build
```

Watch the worker logs for lines like:

```
[event][heartbeat] id=...
[event][progress] id=... progress=0.5 data={step: 5, total: 10}
```

## Observe Worker Heartbeats (CLI)

From the host, point the CLI at Redis and query worker snapshots:

```bash
export STEM_BROKER_URL=redis://localhost:6379/0
export STEM_RESULT_BACKEND_URL=redis://localhost:6379/1

just build-cli
just stem observe workers
```

The output includes the worker ID, active count, and the last heartbeat time.

## Local build + Docker deps (just)

```bash
just deps-up
just build
just build-cli
# In separate terminals:
just run-worker
just run-producer
# Or:
just tmux
```

## Notes

- Progress updates are emitted on the worker's in-process `events` stream.
  This example logs those events directly; production systems may forward them
  to metrics/telemetry pipelines.
- Adjust task duration with `STEPS` and `STEP_DELAY_MS` when running the
  producer (defaults: 10 steps at 800ms each).
