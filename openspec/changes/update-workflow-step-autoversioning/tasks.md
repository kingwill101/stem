- [x] Capture the refined auto-versioning expectations in the workflow spec
      delta for this change.
- [x] Extend the adapter workflow store contract tests to cover versioned step
      rewinds, cursor resets, and iteration metadata.
- [x] Update in-memory, Redis, Postgres, and SQLite workflow store
      implementations so rewind, cursor, and suspension data semantics match
      the spec.
- [x] Run `dart format`, `dart analyze`, the relevant `dart test` suites (core
      + adapter contract), and `openspec validate update-workflow-step-autoversioning --strict`.
