# Spike Report: Redis Reclaim Strategy

## Summary
Evaluate Redis Streams reclaim options (XPENDING processing vs. XAUTOCLAIM) for
recovering messages from crashed workers.

## Findings
- `XAUTOCLAIM` (Redis 6.2+) efficiently claims idle messages without scanning
  the pending list manually.
- A background reclaimer running every 30s with `idle > visibilityTimeout`
  performed consistently under load (tested with 1k tasks/s, 8 workers).
- Edge cases: tasks may be delivered twice if the original worker resumes just
  before reclaim; idempotency guidance remains necessary.

## Recommendation
Keep: use `XAUTOCLAIM` with a configurable idle threshold (default 2×
visibility timeout). Document reclaimer interval and include metric counters for
claimed messages.

## Follow-ups
- Add a future spec item to expose reclaim stats via CLI.
