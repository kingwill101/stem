# Proposal: Workflow idempotency helper and guidance

## Problem
Workflow developers must manually craft idempotency keys for external APIs, often duplicating logic or forgetting to reuse stable identifiers across retries. After the durability enhancements, we now have `FlowContext` aware of workflow/run identity, but there is no formal contract or documentation ensuring developers use it consistently.

## Goals
- Provide a first-class helper (e.g. `FlowContext.idempotencyKey(scope)`) documented as the recommended way to derive retry-safe keys for outbound calls.
- Update examples and guides to demonstrate how to plug the helper into external payment/email APIs.
- Add workflow tests that ensure the helper returns stable values across retries.

## Non-Goals
- Changing existing API signatures that already accept idempotency tokens.
- Implementing automated idempotency enforcement at the store/broker level.
- Revisiting task-level idempotency helpers.

## Measuring Success
- Tests confirm `FlowContext.idempotencyKey` returns the same value across retries and iterations (when auto-versioning is enabled).
- README/example updates show developers how to use the helper in common scenarios.
- Spec coverage captures the requirement so future refactors preserve the helper.
