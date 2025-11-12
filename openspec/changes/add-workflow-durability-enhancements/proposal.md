# Proposal: Strengthen workflow durability semantics

## Problem
Developers adopting Stem's workflow runtime are still exposed to avoidable replay and race behaviours:
- Step checkpoints do not refresh worker leases, increasing overlap risk for long-running steps when a claim expires mid-execution.
- Suspension primitives (`sleep`, `awaitEvent`) rely on runtime polling without persisting wake metadata, so mis-authored steps can repeatedly re-suspend or lose payloads during race windows.
- There is no first-class helper for deriving idempotency keys from workflow/task identity, leaving outbound integrations to craft ad-hoc formats.

## Goals
- Guarantee that committed checkpoints extend run leases across Redis, Postgres, and SQLite stores so a single worker retains ownership while making progress.
- Make suspension flows race-free by persisting wake timestamps/event payloads in the store, allowing resumed steps to fall through without re-scheduling.
- Provide a documented helper for generating stable idempotency keys from workflow identity so external calls can stay idempotent across retries.

## Non-Goals
- Replacing existing timer/event polling loops with new infrastructure.
- Adding support for new workflow backends.
- Introducing exactly-once guarantees; the focus is on reducing duplicate execution windows.

## Measuring Success
- Contract tests demonstrate that calling `saveStep` (or equivalent) extends lease expirations in each store implementation.
- End-to-end workflow tests show a suspended step that already slept resumes without re-scheduling and that awaited events deliver payloads exactly once.
- Documentation/examples show developers using a runtime-provided `idempotencyKey` helper instead of hand-rolled formats.

## Timeline / Rollout
- Land store/runtime improvements behind feature-complete tests.
- Update documentation and examples within the same release since behaviour changes are backwards compatible.
