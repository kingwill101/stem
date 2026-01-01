# Scheduler Observability Demo

This demo highlights Beat scheduler drift metrics, schedule-entry signals, and
CLI inspection workflows using a Redis-backed schedule store.

## Topology

- **Redis** – broker, result backend, and schedule store.
- **Beat** – dispatches scheduled tasks and emits scheduler metrics.
- **Worker** – executes scheduled tasks.

## Quick Start

```bash
cd example/scheduler_observability
# or from repo root:
# cd packages/stem/example/scheduler_observability

just deps-up
just build
just seed

# In separate terminals:
just run-beat
just run-worker

# Or use tmux:
just tmux
```

The Beat process prints schedule-entry signals:

```
[signal] schedule due id=scheduler-fast next=...
[signal] schedule dispatched id=scheduler-fast drift=12ms
```

Metrics are emitted as JSON lines (console exporter). Look for:

- `stem.scheduler.due.entries`
- `stem.scheduler.overdue.entries`
- `stem.scheduler.dispatch.duration`
- `stem.scheduler.drift`

## CLI Checks

Build the CLI once, then inspect schedules:

```bash
just build-cli
just stem schedule list
just stem observe schedules
```

These commands read the Redis schedule store and summarize due/overdue counts.

## Notes

- `schedules.yaml` defines two interval schedules with jitter to create drift.
- Set `STEM_METRIC_EXPORTERS=otlp:http://localhost:4318/v1/metrics` if you want
  to stream scheduler metrics into the OTLP stack from `example/otel_metrics`.
