# Changelog

## 0.1.0

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
