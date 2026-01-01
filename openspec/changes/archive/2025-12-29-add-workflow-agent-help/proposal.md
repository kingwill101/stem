# Proposal: Workflow agent helper output

## Problem
We rely on AGENTS.md and manual documentation for AI/dev assistants, but there is no structured command to emit workflow-specific guidance (e.g. how to inspect waiters, cancel runs safely). Absurd’s `absurdctl agent-help` auto-generates targeted instructions. We should offer a similar capability so teams can keep AGENTS/CLAUDE docs up-to-date.

## Goals
- Add a CLI command (`stem wf agent-help` or similar) that prints workflow-specific guidance for assistants (commands summary, safety notes).
- Document how to use the command to refresh AGENTS/CLAUDE files.
- Ensure the output stays in sync with new CLI features (waiters, leases, etc.).

## Non-Goals
- Generating full interactive documentation (handled elsewhere).
- Covering non-workflow features (tasks, scheduler) in this command; they may have separate helper commands.

## Measuring Success
- Running `stem wf agent-help` prints actionable guidance covering workflow commands, inspection, cancellation, and idempotency advice.
- Teams can copy/paste into AGENTS.md.
