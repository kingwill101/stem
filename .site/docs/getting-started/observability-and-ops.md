---
title: Observe & Operate
sidebar_label: Observe & Operate
sidebar_position: 4
slug: /getting-started/observability-and-ops
---

With Redis/Postgres in place, it’s time to watch the system run. This guide
covers telemetry, worker heartbeats, DLQ tooling, and the remote-control
channel—all the pieces you need to operate Stem confidently.

## 1. Enable OpenTelemetry Export

Stem emits metrics, traces, and structured logs out of the box. Point it at an
OTLP endpoint (the repo ships a ready-made stack under `examples/otel_metrics/`):

```bash
# Start the example collector, Prometheus, and Grafana stack.
docker compose -f examples/otel_metrics/docker-compose.yml up

# Export OTLP details for producers and workers.
export STEM_OTLP_ENDPOINT=http://localhost:4318
export STEM_OTLP_HEADERS="authorization=Basic c3RlbTpwYXNz"
export STEM_OTLP_METRICS_INTERVAL=10s
export STEM_LOG_FORMAT=json
```

In Dart, no extra code is required—the env vars activate exporters. Metrics
include queue depth, retry counts, lease renewals, and worker concurrency;
traces connect `Stem.enqueue` spans with worker execution spans so you can
follow a task end-to-end.

## 2. Inspect Worker Heartbeats & Status

Workers publish detailed heartbeats (in-flight counts, leases, queues) to the
result backend. Use the CLI to view them live:

```bash
# Snapshot the latest heartbeat for every worker.
stem worker status \
  --broker "$STEM_BROKER_URL" \
  --result-backend "$STEM_RESULT_BACKEND_URL"

# Stream live updates (press Ctrl+C to stop).
stem worker status \
  --broker "$STEM_BROKER_URL" \
  --result-backend "$STEM_RESULT_BACKEND_URL" \
  --stream
```

From Dart you can pull the same data:

```dart
final backend = await RedisResultBackend.connect(
  Platform.environment['STEM_RESULT_BACKEND_URL']!,
);
final heartbeats = await backend.listWorkerHeartbeats();
for (final hb in heartbeats) {
  print('${hb.workerId} -> queues=${hb.queues} inflight=${hb.inflight}');
}
```

## 3. Operate Workers via the Control Channel

Stem exposes a built-in control bus so you can interact with workers without
SSH or custom wiring.

```bash
# Discover workers and latency.
stem worker ping --broker "$STEM_BROKER_URL"

# Collect stats (queues, concurrency, runtimes) as JSON.
stem worker stats --json --broker "$STEM_BROKER_URL"

# Revoke a problematic task globally (optionally terminate in-flight).
stem worker revoke 1f23c6a1-... \
  --terminate \
  --broker "$STEM_BROKER_URL"

# Issue a warm shutdown to drain work gracefully.
stem worker shutdown \
  --worker default@host-a \
  --broker "$STEM_BROKER_URL"
```

Need to manage multiple instances on one host? Ship the bundled daemonization
templates or lean on the multi-wrapper:

```bash
# Launch and supervise multiple workers with templated PID/log files.
stem worker multi start alpha beta \
  --pidfile /var/run/stem/%n.pid \
  --logfile /var/log/stem/%n.log \
  --command "/usr/bin/dart run bin/worker.dart"

# Drain and stop the same fleet.
stem worker multi stop alpha beta
```

## 4. Manage Queues, Retries, and DLQ

The CLI exposes queues, retries, and dead letters so operators can recover
quickly.

```bash
# List in-flight tasks with attempts, ETA, and priority.
stem observe tasks list \
  --broker "$STEM_BROKER_URL" \
  --queue default

# Drill into a single task's status (including canvas/group metadata).
stem observe tasks show \
  --result-backend "$STEM_RESULT_BACKEND_URL" \
  --id "$TASK_ID"

# Inspect the dead-letter queue with pagination.
stem dlq list default --page-size 20

# Replay failed tasks back onto their original queues.
stem dlq replay default --limit 10 --confirm
```

Behind the scenes the CLI talks to the same Redis data structures used by
workers, so you see the exact state the runtime is using.

## 5. Alert on Scheduler Drift & Schedules

Beat records run history, drift, and errors. Keep an eye on it with:

```bash
stem observe schedules \
  --store "$STEM_SCHEDULE_STORE_URL" \
  --summary

stem schedule dry-run cleanup-weekly --count 5
```

These commands surface the same drift metrics your Grafana dashboards chart and
help confirm schedule definitions before they go live.

## 6. React to Signals for Custom Integrations

Signals fire for task, worker, and scheduler lifecycle events. Wire them into
chat, incident tooling, or analytics:

```dart title="lib/analytics.dart"
import 'package:stem/stem.dart';

void installAnalytics() {
  StemSignals.taskRetry.connect((payload) {
    print('Task ${payload.envelope.name} retry ${payload.attempt}');
  });

  StemSignals.workerHeartbeat.connect((payload) {
    if (payload.worker.inflight > 100) {
      // Send to your alerting system.
    }
  });

  StemSignals.scheduleEntryFailed.connect((payload) {
    print('Scheduler entry ${payload.entryId} failed: ${payload.error}');
  });
}
```

Combine signal handlers with telemetry to build rich observability without
scattering logic across the codebase.

## 7. Next Stop

You now have dashboards, CLI tooling, and remote control over workers. Finish
the onboarding journey by applying security hardening, TLS, and production
checklists in [Prepare for Production](./production-checklist.md).

If you want more hands-on drills:

- Run `example/ops_health_suite` to practice `stem health` and `stem observe` flows.
- Run `example/scheduler_observability` to watch drift metrics and schedule signals.
