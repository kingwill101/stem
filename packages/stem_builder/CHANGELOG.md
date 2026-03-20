# Changelog

## 0.1.0

- Flattened generated single-argument workflow/task definitions so one-field
  annotated workflows/tasks emit direct typed refs instead of named-record
  wrappers.
- Switched generated output to a bundle-first surface with `stemModule`, `StemWorkflowDefinitions`, `StemTaskDefinitions`, generated typed wait helpers, and payload codec generation for DTO-backed workflow/task APIs.
- Removed generated task-specific enqueue/wait extension APIs in favor of the
  shared `TaskCall.enqueue(...)` and `TaskDefinition.waitFor(...)` surface
  from `stem`, reducing duplicate happy paths in generated task code.
- Added builder diagnostics for duplicate or conflicting annotated workflow checkpoint names and refreshed generated examples around typed workflow refs.
- Refreshed generated child-workflow examples and docs to use the unified
  `startWith(...)` / `startAndWaitWith(...)` helper surface inside durable
  workflow contexts.
- Clarified the builder README to treat direct `WorkflowRuntime` usage as a
  low-level path and prefer app helpers for the common case.
- Added typed workflow starter generation and app helper output for annotated
  workflow/task definitions.
- Switched generated output to per-file `part` generation using `.stem.g.dart`
  files instead of a shared standalone registry file.
- Added support for plain `@WorkflowRun` entrypoints and configurable starter
  naming in generated APIs.
- Refreshed the builder README, example package, and annotated workflow demos
  to match the generated `tasks:`-first runtime wiring.
- Switched generated script metadata from `steps:` to `checkpoints:` and
  expanded docs/examples around direct step calls, context injection, and
  serializable parameter rules.
- Initial builder for annotated Stem workflow/task registries.
- Expanded the registry builder implementation and hardened generation output.
- Added build configuration, analysis options, and tests for registry builds.
- Updated dependencies.
