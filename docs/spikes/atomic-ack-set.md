# Spike Report: Atomic ACK + Result Write

## Summary
Investigate combining broker acknowledgement and result backend update into a
single atomic operation when both are Redis.

## Findings
- Lua script performing `XACK` followed by `SET` in one transaction works and
  adds ~0.3ms latency compared to separate calls.
- Error handling needs careful mapping: if the script fails, the message
  remains pending and the handler replays on retry.
- Non-Redis backends cannot benefit; we need a pluggable mechanism to avoid
  coupling core logic to Redis-specific scripts.

## Recommendation
Discard for now: keep separate operations in v1. The performance gain is modest
and increases complexity. Document the optional optimisation for future release
(behind feature flag or adapter-specific hook).

## Follow-ups
- Track as backlog item if high-throughput use cases demand it.
