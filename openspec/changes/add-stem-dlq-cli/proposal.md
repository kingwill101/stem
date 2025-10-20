## Summary
- Add first-class `stem dlq` management commands so operators can inspect, sample, replay, and purge dead letters safely.
- Extend broker/backend contracts where needed so replayed envelopes re-enter normal routing with metadata preserved.

## Motivation
- Current spec promises DLQ visibility but lacks tooling for replay or inspection; operators have no way to recover tasks besides manual DB poking.
- We need a predictable CLI flow before teams can run Stem in production.

## Goals
- Provide ergonomic CLI subcommands for listing queues, inspecting entries (with sampling), replaying in batches, and purging with confirmation.
- Preserve envelope metadata (attempt counters, headers, DLQ reason) when replaying so handlers can implement idempotency.
- Ensure Redis broker/backend integrations expose the minimal APIs the CLI needs (pagination, replay hooks).

## Non-Goals
- Building a graphical dashboard (covered by other changes).
- Adding advanced replay scheduling (e.g., cron-based drains) beyond immediate or delayed replay.

## Risks & Mitigations
- **Accidental mass replay**: Require explicit queue argument, dry-run output, and confirmation prompts; support `--limit` and `--since` filters.
- **Replay storms**: Rate-limit requeue operations and document batching defaults.
- **Inconsistent metadata**: Add integration tests to confirm backend/broker keep DLQ trace data intact.

## Open Questions
- Should replayed tasks increment the attempt counter or reset it? (Proposal default: increment to reflect another try.)
- Do we need per-tenant filtering now or later? (Default to global filters, design sensibly for future extension.)
