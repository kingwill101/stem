# Stem v1 Design Doc

## Executive Summary
Stem provides a Dart-native background job platform built on Redis Streams with
OpenTelemetry-first observability. The v1 release targets at-least-once delivery
with configurable retries, time limits, and a CLI-first operator surface.

## Goals
- Reliable enqueue → execute → result flow for Dart services.
- Production-ready Redis Streams broker + Redis result backend.
- Built-in observability (metrics, traces, logs) and operational tooling.
- Clear public interface contract for adapters and middleware.

## Non-Goals
- Exactly-once guarantees or deduplicated delivery.
- Non-Redis adapters (RabbitMQ/SQS) in the v1 timeframe.
- Full UI dashboard (CLI + docs only).

## System Overview
```
   +-----------+        +-----------------+        +--------------------+
   |  Client   | -----> | Redis Streams    | -----> | Worker (isolate pool)|
   +-----------+        +-----------------+        +--------------------+
         |                     |   |                         |
         |                     |   |                         v
         |                     |   |                +----------------+
         |                     |   +--------------> | Result Backend |
         |                     |                    +----------------+
         |                     |                            |
         |                     v                            v
         |             +-----------------+        +--------------------+
         +-----------> | Beat (scheduler)| -----> | Broker (delayed)   |
                       +-----------------+        +--------------------+
```

- **Client** uses the `Stem` facade to enqueue tasks.
- **Broker** stores envelopes and delivers them to workers.
- **Worker** executes tasks in isolates, renews leases, updates backend.
- **Result backend** persists task status and supports chords/groups.
- **Beat** schedules recurring tasks via Redis ZSET.

## Message Schema (Envelope)
| Field | Type | Notes |
| --- | --- | --- |
| `id` | `String` | Generated via timestamp + random suffix. |
| `name` | `String` | Qualified task name. |
| `args` | `Map<String, Object?>` | JSON-serialisable arguments. |
| `headers` | `Map<String, String>` | Metadata (traceparent, tenant). |
| `enqueuedAt` | `DateTime` (ISO8601, UTC) | Creation timestamp. |
| `notBefore` | `DateTime?` | Optional ETA. |
| `priority` | `int` | Adapter-specific priority. |
| `attempt` | `int` | Delivery attempt (0-based). |
| `maxRetries` | `int` | Maximum retry count. |
| `visibilityTimeout` | `Duration?` (ms) | Lease duration hint. |
| `queue` | `String` | Logical queue name. |
| `meta` | `Map<String, Object?>` | User metadata and system fields. |

## Task State Model
```
  queued -> running -> succeeded
             |            |
             v            v
           retried -----> failed
                          |
                          v
                        dead-lettered
```
- Each transition recorded in the result backend with timestamps and metadata.
- Retries increment `attempt` and re-enqueue with backoff.

## Delivery Semantics
- At-least-once delivery with idempotent handler recommendation.
- Workers ack **after** successful execution/state write.
- Failed tasks NACKed or dead-lettered when retries exhausted.
- Leases renewed at half intervals; unacked messages reclaimed via XAUTOCLAIM.

## Time Limits, Prefetch, Rate Limiting
- **Soft limit**: raises a timeout event for observability.
- **Hard limit**: isolates interrupted/killed, task retried.
- **Prefetch**: configurable `concurrency * multiplier` (default ×2).
- **Rate limiting**: token bucket via `RateLimiter` interface; per-task keys by default.

## Adapters (MVP)
- Broker: Redis Streams (Streams + ZSET for delays + XAUTOCLAIM for reclaim).
- Result backend: Redis Hash + TTL, group aggregation.
- Scheduler: Redis ZSET-based beat.

## Configuration Model
1. Environment variables (`STEM_*`).
2. Optional `YAML`/`JSON` config file (future work).
3. Code overrides via constructors.

Precedence: code overrides > config file > env vars.

## Security
- TLS support for Redis URIs; document secret rotation via env vars.
- Optional payload signing/encryption: future extension (documented as TODO).
- No admin endpoints; CLI uses same credentials as workers.
- Threat model highlights: broker compromise (mitigate with ACL/TLS), replay attacks (trace + idempotency), credential leakage (secret rotation policy).

## Observability & SLOs
- Metrics: `stem.tasks.*`, `stem.worker.inflight`, `stem.queue.depth`, `stem.lease.renewed`, beat metrics.
- Traces: enqueue → consume → execute spans with W3C context propagation.
- Logs: structured with `traceId`, `spanId`, task metadata.
- Example SLOs:
  - Success rate ≥ 99.5% over a 15-minute window.
  - Worker task latency p95 < 3 seconds over 5 minutes.
  - Default queue depth < 100 messages sustained for 10 minutes.

## Risks & Mitigations
| Risk | Mitigation |
| --- | --- |
| Chord fan-in overload | throttle callbacks, shard result storage. |
| Global rate limits precision | document approximate guarantees; leverage Redis scripts. |
| Duplicate execution | encourage idempotent tasks; provide helper utilities. |
| Redis outage | surface metrics/alerts; document failover runbook. |

## Sign-off
- [ ] Lead Engineer: ____________________
- [ ] Product/PM: ____________________
- [ ] Ops/On-call: ____________________
