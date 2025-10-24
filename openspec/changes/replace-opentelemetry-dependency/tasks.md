## Tasks
- [x] Audit the codebase for `opentelemetry` imports and map each usage to the equivalent `dartastic_opentelemetry` API.
- [x] Refactor tracing, worker, and Stem core modules to use `dartastic_opentelemetry` exclusively; remove the `opentelemetry` dependency from `pubspec.yaml`.
- [x] Update tests, examples, and docs to reflect the new telemetry stack, including configuration guidance for exporters.
- [x] Run `dart format`, `dart analyze`, targeted unit/integration tests, and `openspec validate replace-opentelemetry-dependency --strict`.
