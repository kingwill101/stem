# Spike Report: Isolate Hard Timeouts

## Summary
Prototype running task handlers inside isolates with hard timeouts enforced via
`Future.timeout` and isolate termination.

## Findings
- Spawning isolates via `TaskIsolatePool` adds ~1.5ms overhead per task at
  concurrency 32; acceptable for background jobs.
- Killing isolates after exceeding hard timeout reliably aborted long-running
  tasks; leaked isolates were replaced in the pool without memory growth.
- Awaited work must be cancellable; blocking synchronous work still holds CPU
  until the isolate is terminated (documented as limitation).

## Recommendation
Keep: retain isolate wrappers with hard timeout enforcement. Provide
configuration knobs for pool size and hard timeout per task. Document best
practices for cooperative cancellation where possible.

## Follow-ups
- Consider exposing a metric for hard-timeout occurrences.
