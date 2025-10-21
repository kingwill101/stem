---
id: observability-runbook
title: Observability Runbook
sidebar_label: Observability Runbook
---

## SLOs

| Service Aspect | Target | Measurement Window | Notes |
| --- | --- | --- | --- |
| Task success rate | ≥ 99.5% | 15 minutes | Alert: `stem-task-success-rate`; ratio of succeeded vs. started |
| Task latency (p95) | < 3 seconds | 5 minutes | Alert: `stem-task-latency`; histogram quantile over five-minute slice |
| Queue depth (default) | < 100 messages | 10 minutes | Alert: `stem-queue-depth`; monitors sustained backlog growth |

## Dashboards

1. **Worker Health**
   - `stem.worker.inflight` (per worker)
   - `stem.tasks.{started,succeeded,failed,retried}` rate
   - Heartbeat freshness (latest timestamp per worker)
2. **Queue Health**
   - `stem.queue.depth` gauge per queue
   - Redis pending count vs. in-flight
3. **DLQ Overview**
   - Dead-letter counts by reason
   - Oldest DLQ entry age
4. **Beat Metrics**
   - Schedule fires per entry
   - Observed jitter/skew

## Alerts

- **stem-task-success-rate** (critical): fires when success ratio falls below 99.5% for 5 minutes.
- **stem-task-latency** (critical): fires when task execution p95 exceeds 3 seconds for 5 minutes.
- **stem-queue-depth** (warning): fires when queue depth exceeds 100 messages for 10 minutes.
- Legacy watches remain in Prometheus for heartbeats, DLQ age, reclaim spikes, and beat skew; convert them to Grafana alerts in a future phase.

## Runbook Steps

1. **Task Success Rate < 99.5%**
   - Open the Grafana panel “Task Success Rate” and switch the time picker to 15 minutes.
   - Correlate spikes in `stem_tasks_failed_total` and check recent deploys.
   - Sample failing envelopes via `stem dlq list --queue <queue> --limit 20` (include default queue if unspecified).
   - If a single task type regresses, disable or rate-limit it until a hotfix ships; otherwise escalate to the feature team owning the workload.
2. **Task Latency p95 ≥ 3s**
   - Inspect the “Task Latency Percentiles” panel to confirm whether latency is isolated to specific tasks.
   - Check worker isolate saturation (`stem.worker.inflight`) and CPU metrics on the hosts.
   - Verify external dependencies (databases, HTTP services) for elevated response times.
   - Scale workers or throttle slow tasks while investigating root cause.
3. **Queue Depth > 100**
   - Review the “Queue Depth” panel to identify which queues are backing up.
   - Confirm that consumers are running (heartbeat panel) and that prefetch limits aren’t capping throughput.
   - Inspect broker health (Redis latency, memory pressure). If broker is healthy, add temporary worker capacity.
   - After catching up, right-size concurrency or adjust rate limits to prevent recurrence.
4. **Legacy Alerts (Heartbeats, DLQ, Reclaim)**
   - Continue to follow existing procedures: reclaim stuck tasks, replay DLQ entries, and audit heartbeat freshness per the legacy checklist.

## Ownership

- Primary: Observability on-call engineer (`pagerduty://stem-sre-primary`).
- Escalation: post in `#stem-ops` and page the engineering manager if unresolved after 30 minutes.
- Update SLOs quarterly or after major architecture changes.
