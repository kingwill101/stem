# Proposal: Expand Stem Task Ergonomics and Tooling

## Background
After enforcing stronger registry semantics and introducing typed task
definitions, the ecosystem still leans heavily on ad-hoc enqueue code and lacks
ops-facing visibility into task metadata. We want to streamline authoring,
adoption, and observability for teams building on Stem.

## Goals
- Provide fluent builders and generators that reduce boilerplate when enqueuing
  tasks or creating typed definitions.
- Surface task metadata in the CLI so operators can inspect available tasks,
  descriptions, idempotency flags, and tags.
- Allow tooling to react to registration changes at runtime.
- Supply testing helpers for capturing enqueued jobs.
- Enrich tracing with task metadata.

## Non-Goals
- We will not introduce a full analyzer plugin in this iteration; linting will
  focus on reusable utilities developers can import manually.
- No changes to scheduler or worker internals beyond metadata propagation.
