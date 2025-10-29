# Proposal: Enhance Task Registry and Enqueue APIs

## Background
The core Stem runtime currently relies on `SimpleTaskRegistry` to map task names
to handlers. The registry silently overwrites existing handlers on duplicate
registration and offers no way to introspect registered tasks or surface
metadata to tooling. Producers also enqueue tasks by passing raw `Map` payloads
to `Stem.enqueue`, which increases the chances of runtime errors when typed
arguments change or when optional headers/options are omitted.

To improve safety and ergonomics we want the registry to enforce uniqueness,
expose metadata for CLI/dashboard consumers, and ship typed helpers that make
building enqueue requests less error-prone.

## Goals
- Detect duplicate task registrations unless overrides are explicitly allowed.
- Provide a simple metadata surface so tooling can list registered tasks and
  developers can attach documentation, tags, and behavioral flags.
- Add typed enqueue helpers that wrap task definitions, ensuring argument
  encoding stays centralized and testable.
- Back the changes with comprehensive unit tests.

## Non-Goals
- We are not introducing new backends or modifying broker behavior.
- No changes to scheduler/task execution semantics beyond registry lookups.
- CLI/dashboard wiring that consumes the new metadata will follow later.
