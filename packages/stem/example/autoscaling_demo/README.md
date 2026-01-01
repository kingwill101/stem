# Autoscaling Demo

This demo exercises Stem's worker autoscaler by flooding a Redis-backed queue
and watching concurrency scale up/down. Metrics are emitted via the console
exporter by default so you can verify the autoscaler decisions.

## Topology

- **Redis** – broker + result backend.
- **Worker** – autoscaling worker on the `autoscale` queue.
- **Producer** – enqueues bursts of work to trigger scaling.

## Quick Start

```bash
cd example/autoscaling_demo
# or from repo root:
# cd packages/stem/example/autoscaling_demo

just deps-up
just build

# In separate terminals:
just run-worker
just run-producer

# Or use tmux:
just tmux
```

You should see log lines like:

```
Adjusted concurrency from 1 to 2 (scale-up)
Adjusted concurrency from 2 to 3 (scale-up)
Adjusted concurrency from 3 to 2 (scale-down)
```

Console metrics are emitted as JSON. Look for `stem.worker.concurrency` and
`stem.queue.depth` events to verify autoscaler behavior.

## Tunables

Set environment variables to change the workload or autoscale profile:

- `WORKER_CONCURRENCY` (default: 6)
- `AUTOSCALE_MIN` / `AUTOSCALE_MAX`
- `AUTOSCALE_BACKLOG_PER_ISOLATE` (default: 2)
- `AUTOSCALE_TICK_MS`, `AUTOSCALE_IDLE_MS`
- `AUTOSCALE_UP_COOLDOWN_MS`, `AUTOSCALE_DOWN_COOLDOWN_MS`
- `TASKS`, `BURST`, `PAUSE_MS`, `TASK_DURATION_MS`

To export metrics to OTLP instead of stdout, set:

```bash
STEM_METRIC_EXPORTERS=otlp:http://localhost:4318/v1/metrics
```

(See `example/otel_metrics` for a ready-made Grafana stack.)
