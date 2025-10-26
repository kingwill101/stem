# ADR 0003: Retry Policy Defaults & DLQ Shape

## Status
Accepted (v1).

## Context
We need sensible defaults for retry behaviour that align with at-least-once
semantics and provide a clear route to dead-letter queues.

## Decision
- Default `maxRetries = 3` with exponential backoff + jitter (2s base).
- After exhausting retries, publish to per-queue dead-letter streams with reason
  metadata (`retryDelayMs`, error summary).
- CLI tooling exposes list/show/replay/purge operations on DLQs.

## Consequences
- Developers can override retry strategy per task but opt-outs still require
  idempotent handlers.
- Dead-letter entries persist with TTL configured by result backend.
- Observability metrics track retries (`stem.tasks.retried`) and DLQ replay
  counts to surface remediation activity.
