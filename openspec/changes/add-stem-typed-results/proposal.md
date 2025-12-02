# Proposal: Typed task, canvas, and chord results across Stem

## Problem
Stem's task APIs already provide typed argument encoders (`TaskDefinition`,
`TaskCall`, `TaskEnqueueBuilder`), but every API that observes task results
exposes raw `TaskStatus` objects with `Object? payload`. Producers, CLI tools,
chords, and canvas helpers all downcast payloads manually, duplicating deserial-
ization logic and making it easy to forget error-status checks before using
results. Now that workflows offer typed completion helpers, the rest of the
platform feels inconsistent: task authors expect similar ergonomics when
waiting on individual tasks, group/chord callbacks, or canvas chains that pass
results between steps.

## Goals
- Introduce generic result wrappers for Stem's task-facing APIs so callers can
  declare the expected payload type once and re-use it for queues, chains,
  groups, and chords without runtime casting.
- Provide optional decoder hooks everywhere raw `Object?` payloads surface so
  services can plug in structured JSON → domain converters while defaulting to
  simple casts for primitives.
- Ensure canvas primitives (chain/group/chord) propagate typed payloads between
  steps and to callbacks so downstream handlers can rely on concrete types.
- Keep result backend persistence unchanged—stores continue to write raw
  payloads; typing happens in the Stem/canvas helpers that consume them.

## Non-Goals
- Changing task execution semantics, retry strategies, or backend schemas.
- Enforcing typed payloads inside worker isolates (handlers may still return
  any JSON-serializable object).
- Replacing the existing raw `TaskStatus` APIs entirely; low-level callers can
  keep using them when they need full access to backend metadata.

## Measuring Success
- Task producers can `await stem.waitForTask<MyType>(taskId, decode: ...)` (or
  equivalent) and receive typed payloads plus TaskStatus metadata without
  writing glue code.
- Canvas `chain` helpers propagate typed values between steps, and chords
  expose `List<MyType>` (or decoder output) to callbacks with compile-time
  safety.
- CLI/docs/examples demonstrate the typed APIs, mirroring the workflow
  experience so the platform feels consistent regardless of feature area.
