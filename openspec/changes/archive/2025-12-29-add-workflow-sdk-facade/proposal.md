# Proposal: Add workflow DSL facade with step/await/sleep helpers

## Problem
The current workflow API exposes `FlowBuilder` directly, forcing authors to
manually split each step into separate callbacks and manage state through
`FlowContext`. Absurd ships a higher-level `TaskContext` facade that lets
developers write imperative code (`await ctx.step(...)`, `await ctx.awaitEvent`)
inside one async function. Without a similar layer, Stem workflows end up verbose,
hard to refactor, and users often miss critical durability rules (e.g. when a
step replays after `sleep`).

## Goals
- Provide an ergonomic Dart-first facade that wraps `FlowBuilder` so developers
  can express workflows with sequential `await ctx.step` calls, while still
  honoring durability semantics.
- Surface dedicated helpers for `sleep`, `awaitEvent`, and versioned steps in
  the facade to match Absurd’s TaskContext ergonomics.
- Document the new facade prominently so developers understand when to use it
  versus the lower-level `FlowBuilder`.

## Non-Goals
- Removing or breaking the existing `FlowBuilder` API.
- Building new visual tooling for the DSL (diagramming, code generation).
- Changing suspension semantics or the workflow runtime beyond what the facade
  needs for parity.

## Measuring Success
- A new DSL lets workflows be written in a single async function and is covered
  by unit and integration tests (including the shared adapter contract suite)
  that prove durability parity with the underlying Flow API.
- Docs and examples showcase both the existing builder and the new facade, with
  guidance on when to pick each.
- Developers adopting the facade can leverage `ctx.step`, `ctx.sleep`, and
  `ctx.awaitEvent` without re-learning low-level stores, matching Absurd’s
  ergonomics.

## Rollout
- Ship the facade, tests, and docs together as part of the next Stem release.
- Treat the facade as additive and backward compatible so existing workflows
  stay untouched.
