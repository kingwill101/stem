## Context
Workflow definitions today require manual registration and explicit wiring, which is verbose for Temporal-style patterns (class-based workflows with annotated steps). Dart lacks runtime mirrors in most environments, so we need a build-time registry approach.

## Goals / Non-Goals
- Goals:
  - Provide ergonomic annotations for workflows, steps, and tasks.
  - Generate a registry at build time for discovery and execution.
  - Keep runtime API small and explicit (opt-in, no global magic).
- Non-Goals:
  - No runtime reflection or mirrors.
  - No automatic discovery without build_runner/codegen.
  - No changes to workflow execution semantics (only definition ergonomics).

## Decisions
- Decision: Use `source_gen` + `build_runner` to generate a registry file per package.
  - Rationale: avoids mirrors, keeps tree-shaking, and aligns with existing Dart tooling.
- Decision: Annotations live in `packages/stem` with minimal runtime footprint; generator lives in a new package (name TBD, e.g., `stem_builder`).
- Decision: Generated registry exposes a single entrypoint `registerStemDefinitions(StemRegistry registry)` to opt-in at app startup.

## Risks / Trade-offs
- Requires build_runner setup in consuming apps (extra dev dependency).
- Naming/ID stability for workflows/steps must be specified to prevent accidental renames.

## Migration Plan
1. Add annotations and generator.
2. Provide example usage and opt-in registry loading.
3. Add tests for generated registry wiring.

## Open Questions
- Exact naming rules for workflow/step identifiers (default to class/method name vs. explicit override).
- Where to place generator package (top-level `packages/` or `tool/`).
