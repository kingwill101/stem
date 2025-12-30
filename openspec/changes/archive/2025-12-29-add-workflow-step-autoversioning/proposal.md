# Proposal: Add auto-versioned workflow steps

## Problem
Workflow steps are single-shot today: once a checkpoint for `flow.step('foo')` exists, the runtime always skips re-execution. Developers who need to iterate (e.g. looping over items, polling until a condition, or resuming the same step multiple times) must create unique step names manually (`foo-1`, `foo-2`, ...). This is error-prone, brittle during refactors, and makes dynamic loops awkward or impossible when the number of iterations is not known in advance.

## Goals
- Provide an ergonomic way to opt a step into automatic versioning so each execution stores a unique checkpoint (`foo#1`, `foo#2`, ...).
- Ensure versioned steps resume correctly: checkpoints hydrate by iteration and the runtime only replays the unfinished iteration after crashes or suspensions.
- Maintain backwards compatibility: existing steps keep single execution semantics unless explicitly marked repeatable.

## Non-Goals
- Changing the default behaviour for existing steps.
- Implementing higher-level loop constructs; we focus on checkpoint naming and replay semantics.
- Revisiting how step order is listed in stores beyond storing sequential metadata.

## Measuring Success
- Contract tests demonstrate that a versioned step can persist multiple checkpoints across iterations and resumes at the correct iteration after a failure.
- Developers can implement looping patterns (e.g. process items until queue empty) without manually synthesizing step names.
- Documentation/examples illustrate the new API and warn about idempotency expectations per iteration.

## Rollout
- Ship runtime + store changes along with tests and doc updates in one release.
- Adapters (Redis/Postgres/SQLite) update in lock-step to respect versioned checkpoint keys.
