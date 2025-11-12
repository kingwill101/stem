# Proposal: Workflow cancellation policy enforcement

## Problem
Workflow runs can suspend indefinitely today. Developers can simulate deadlines manually (e.g. checking timers or storing metadata), but there is no built-in cancellation policy or documentation guiding them. Operators also struggle to cancel runs automatically when they exceed business-defined limits. Absurd highlighted per-task cancellation policies applied by stores; Stem should offer similar behaviour.

## Goals
- Allow developers to specify a cancellation policy (max runtime, max suspension duration) when starting workflows.
- Ensure stores persist policy metadata and the runtime enforces cancellation once thresholds are exceeded.
- Expose cancellation reasons via signals and CLI so operators can inspect automatic cancellations.

## Non-Goals
- Implementing multi-step SLAs or per-step timeouts beyond suspend/overall runtime limits.
- Providing UI automation; CLI/Doc updates suffice.

## Measuring Success
- Tests confirm that workflows exceeding the configured max runtime or suspension duration are automatically cancelled with rationale.
- CLI shows the auto-cancel reason and timestamp.
- Documentation explains how to configure policies and cautions about idempotency.
