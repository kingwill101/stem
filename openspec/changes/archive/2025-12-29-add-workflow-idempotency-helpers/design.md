# Design: Workflow idempotency helper

## Overview
We enrich `FlowContext` with a helper that concatenates workflow name, run ID, and an optional scope to produce a stable idempotency key string. The runtime already knows these values; the helper simply exposes them. We document usage and update tests to guard behaviour.

## Details
- Add `String idempotencyKey([String scope])` to `FlowContext`, defaulting the scope to the current step.
- Ensure auto-versioned steps include the iteration number in their default scope (`step#iteration`) so that each repetition gets a unique default key.
- Document the helper in README + example flows, especially around external APIs (payments, emails).
- Add tests verifying stable values across retries and iteration changes.

## Edge Cases
- Auto-versioned steps should include iteration number automatically to avoid clashing across iterations.
- Developers can override the scope to target sub-operations (e.g. `ctx.idempotencyKey('email')`).

## Risks
Low; helper is additive. The main risk is inconsistent documentation, mitigated by updated examples/tests.
