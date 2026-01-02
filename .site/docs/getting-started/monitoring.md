---
title: Monitoring Guide
sidebar_label: Monitoring
sidebar_position: 11
slug: /getting-started/monitoring
---

This guide focuses on visibility: dashboards, metrics, and signals that help
catch issues early.

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Dashboard deployment

- **Local**: run the dashboard on a developer workstation for quick checks.
- **Internal**: deploy behind an auth proxy (SSO, basic auth, or IP allowlist).
- **Shared ops**: place behind a reverse proxy with TLS termination and strict
  access controls.

Restrict control actions to operators and ensure TLS is terminated at the proxy
or upstream load balancer.

See the [Dashboard](../core-concepts/dashboard.md) guide for setup details.

## Key indicators

- **Queue depth**: growing queues indicate stalled workers or upstream spikes.
- **Queue latency**: long gaps between enqueue time and start time point to
  saturation or routing issues.
- **Retry rate**: a rise in retries usually signals transient dependency issues.
- **DLQ volume**: poison pills or schema mismatches show up here.
- **Worker heartbeats**: missing heartbeats point to crashed or partitioned
  workers.
- **Scheduler drift**: drift spikes indicate schedule store or broker delays.

## Signals & metrics

- Use lifecycle signals to emit structured events early.
- Export metrics to your standard stack (OTLP, Prometheus, Datadog, etc.).
- Correlate task IDs with traces/logs.

<Tabs>
<TabItem value="metrics" label="Metrics Exporters">

```dart title="lib/observability.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/observability.dart#observability-metrics

```

</TabItem>
<TabItem value="signals" label="Signal Hooks">

```dart title="lib/observability.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/observability.dart#observability-signals

```

</TabItem>
<TabItem value="queue-depth" label="Queue Depth Gauge">

```dart title="lib/observability.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/observability.dart#observability-queue-depth

```

</TabItem>
<TabItem value="env" label="Env Vars">

```bash
export STEM_METRIC_EXPORTERS=otlp:http://localhost:4318/v1/metrics
export STEM_OTLP_ENDPOINT=http://localhost:4318
```

</TabItem>
</Tabs>

## CLI probes

<Tabs>
<TabItem value="cli" label="CLI Commands">

```bash
stem observe queues
stem observe workers
stem observe schedules
stem worker stats --json
```

Set `STEM_SCHEDULE_STORE_URL` before running `stem observe schedules`.

</TabItem>
<TabItem value="dart" label="Dart (Heartbeats)">

```dart title="lib/observability_ops.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/observability_ops.dart#ops-heartbeats

```

</TabItem>
</Tabs>

## Next steps

- [Observability & Ops](./observability-and-ops.md)
- [Dashboard](../core-concepts/dashboard.md)
- [Worker Control CLI](../workers/worker-control.md)
