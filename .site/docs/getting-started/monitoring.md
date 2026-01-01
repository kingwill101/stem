---
title: Monitoring Guide
sidebar_label: Monitoring
sidebar_position: 11
slug: /getting-started/monitoring
---

This guide focuses on visibility: dashboards, metrics, and signals that help
catch issues early.

## Dashboard deployment

- Run the dashboard behind your standard auth proxy.
- Restrict control actions to operators.
- Ensure TLS is terminated at the proxy or upstream load balancer.

See the [Dashboard](../core-concepts/dashboard.md) guide for setup details.

## Key indicators

- **Queue depth**: growing queues indicate stalled workers or upstream spikes.
- **Retry rate**: a rise in retries usually signals transient dependency issues.
- **DLQ volume**: poison pills or schema mismatches show up here.
- **Worker heartbeats**: missing heartbeats point to crashed or partitioned
  workers.

## Signals & metrics

- Use lifecycle signals to emit structured events early.
- Export metrics to your standard stack (Prometheus, Datadog, etc.).
- Correlate task IDs with traces/logs.

## CLI probes

```bash
stem observe tasks list --broker "$STEM_BROKER_URL"
stem worker stats --broker "$STEM_BROKER_URL" --json
stem observe schedules --store "$STEM_SCHEDULE_STORE_URL"
```

## Next steps

- [Observability & Ops](./observability-and-ops.md)
- [Dashboard](../core-concepts/dashboard.md)
- [Worker Control CLI](../workers/worker-control.md)
