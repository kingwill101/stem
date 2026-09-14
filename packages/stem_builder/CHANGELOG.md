# Changelog

## 0.4.0

- Ship a package skill for generated tasks, workflows, and explicit codec bindings.
- Require Dart `>=3.13.0 <4.0.0` and exercise primary-constructor DTOs in the
  compiler-backed consumer fixture.
- Validate codec representation provenance across flow steps and reject nullable
  codec declarations before emission. Nullable payload types remain supported.
- Add `@PayloadCodecDefn()` bindings for library-local standard
  `Codec<T, Object?>` values and getters. Matching is exact, including
  nullability; duplicate, non-codec, and invalid output bindings are rejected.
  Generated parts retain the binding value rather than wrapping it, so getters
  are evaluated once and concrete codec subtypes are preserved. Generic codec
  inference and reflection remain unsupported.
- Preserve synchronous collection result types by unwrapping only `Future` and
  `FutureOr`. Normalize task entrypoints without erasing their typed results.
- Validate flow step inputs against the starter contract and reject duplicate
  logical task/workflow names during generation.
- Escape Dart interpolation in generated names, metadata, and part directives.
- Preserve null when encoding and decoding nullable generated DTO payloads.
- Add a real consumer fixture that runs build_runner, analyzes generated code,
  checks stable regeneration, and executes inline/isolate tasks and workflows
  against the actual Stem runtime.
- Document standard `dart:convert` codec support in Stem's typed authoring APIs.
  Generated `PayloadCodec.json` helpers remain unchanged and are compatible with
  the standard `Codec` interface in Stem versions that support it.
- Require Stem `>=0.5.0 <1.0.0`, allowing later pre-1.0 releases.

## 0.3.1

- Widened Stem compatibility to include the 0.4 portable runtime line.
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
