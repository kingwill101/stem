# Changelog

## 0.3.0

- Updated the builder for the Stem 0.3.0 release train and Dart 3.12 minimum.
- Updated generated task adapters and workflow definitions for Stem 0.3.0.
- Generated tasks now preserve typed handler boundaries and isolate entrypoints
  without exposing raw map transport code to application code.
- Generated registrations now declare `TaskExecutionMode` explicitly, making
  inline versus isolate execution visible in generated source.

## 0.2.1

- Updated the `stem` dependency range to admit the in-progress `0.2.1-wip`
  core prerelease during workspace resolution.
- Generated task registrations now use `TypedTaskHandler` adapters backed by
  the generated task definition, including generated isolate entrypoints.

## 0.2.0

- Generated output now centers on `stemModule`, `StemWorkflowDefinitions`, and
  `StemTaskDefinitions` with the same narrowed happy-path APIs as `stem`
  itself.
- Generated child-workflow examples and docs now prefer direct
  `start(...)` / `startAndWait(...)` helpers in durable boundaries, leaving
  explicit transport objects as the advanced path.
- Generated DTO payload codecs now use the shorter `json(...)`, `map(...)`,
  and registry-backed versioned factories where appropriate.
- Builder diagnostics now catch duplicate/conflicting workflow checkpoint
  names and redundant manual `script.step(...)` wrappers around annotated
  checkpoints, including context-aware cases.
- Annotated workflow/task generation now supports shared execution contexts,
  direct typed starter output, and bundle-first bootstrap guidance that aligns
  with the `StemClient`-first runtime model.

## 0.1.0

- Initial builder for annotated Stem workflow/task registries.
- Expanded the registry builder implementation and hardened generation output.
- Added build configuration, analysis options, and tests for registry builds.
- Updated dependencies.
