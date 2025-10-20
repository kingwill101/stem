# Observability Runbook

## SLOs
| Service Aspect | SLO | Notes |
| --- | --- | --- |
| Enqueue-to-start latency | p95 < 1s (steady load) | Monitor `stem.queue.depth` + `stem.tasks.started` lag |
| Task duration accounting | p99 error < 100ms | Compare `stem.task.duration` with handler logs |
| DLQ oldest age | < 10 minutes for critical queues | Derive from Redis stream entry timestamps |
| Reclaim latency | < 2× visibility timeout | Track reclaimed count vs. visibility |

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
- Missing heartbeat (>2× heartbeat interval).
- DLQ oldest age exceeds threshold.
- Reclaim count spikes (indicating worker failures).
- Beat skew > configured limit.

## Runbook Steps
1. **No Heartbeats**
   - Check worker logs for crashes.
   - Inspect `stem.worker.inflight` gauge; if stuck >0, consider manual reclaim.
   - Recycle offending worker after dumping isolate stacks if possible.
2. **DLQ Growth**
   - `stem dlq list --queue <q>` to inspect.
   - Identify error patterns; replay small batches after fixes (`stem dlq replay`).
3. **High Latency**
   - Inspect queue depth vs. worker concurrency; scale workers or adjust prefetch.
   - Check rate limiter metrics and Redis performance.
4. **Reclaim Spike**
   - Verify visibility timeout; ensure workers aren't blocking on external IO.
   - Review recent deployments for crashes.

## Ownership
- On-call engineer maintains dashboards/alerts.
- Update SLOs quarterly or after major architecture changes.
