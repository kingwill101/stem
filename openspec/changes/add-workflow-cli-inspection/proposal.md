# Proposal: CLI tooling for workflow inspection

## Problem
Operators currently lack dedicated CLI commands to inspect workflow watchers, leases, and suspension metadata. After adding durable watchers and cancellation policies, we need tooling to surface this data for debugging and operations (mirroring Absurd’s `absurdctl`).

## Goals
- Extend `stem_cli` with commands to list waiting runs per topic, show watcher payloads, and inspect lease/cancellation metadata for a run.
- Provide filters (topic, status) and human-readable summaries (e.g. time until deadline, policy info).
- Update documentation to guide operators on using the new commands.

## Non-Goals
- Building a UI/dashboard (covered by later change).
- Adding mutation commands beyond existing cancel/emit.

## Measuring Success
- Operators can run `stem wf waiters --topic payment.received` and see suspended runs with metadata.
- `stem wf show <runId>` displays lease expiry, suspension data, watchers, and policies.
- Tests cover CLI output parsing (unit/integration depending on CLI architecture).
