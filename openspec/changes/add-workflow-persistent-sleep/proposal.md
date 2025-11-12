# Proposal: Persistent workflow sleep semantics

## Problem
Workflow steps that use `ctx.sleep` are replayed from the top once the delay
elapses. Today handlers must manually call `takeResumeData()` and guard their
logic to avoid re-scheduling another sleep, otherwise the step immediately
suspends again and the workflow never progresses. This boilerplate is easy to
miss, making loop-style workflows hard to author.

## Goals
- Persist wake timestamps in suspension metadata and teach the runtime to skip
  re-suspending when a resumed step calls `sleep` again without checking the
  payload.
- Ensure both Flow and WorkflowScript APIs inherit the behaviour so handlers get
  sane defaults with no extra code.
- Cover the new semantics with adapter/runtime tests so third-party stores stay
  compliant.

## Non-Goals
- Changing the public `sleep` API signature or introducing new scheduling
  primitives.
- Altering event watcher behaviour.
- Providing dynamic backoff logic—handlers can still compute their own delays.

## Measuring Success
- A workflow step that simply calls `ctx.sleep(Duration(seconds: 5)); return;`
  wakes up once and continues without additional guards.
- Contract and runtime tests demonstrate sleep metadata survives across stores
  and prevents double suspension.

## Rollout
- Update runtime/FlowContext to recognise persisted wake timestamps before
  touching store implementations (metadata already exists).
- Ship tests and docs simultaneously so adapters and users adopt the new
  behaviour in the same release.
