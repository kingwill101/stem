## Tasks
- [x] Implement `TaskEnqueueBuilder` producing `TaskCall` instances and convenience helpers in `stem`.
- [x] Extend `TaskRegistry` with `onRegister` stream and wire it inside `SimpleTaskRegistry`.
- [x] Enrich `Stem.enqueue` tracing attributes with handler metadata.
- [x] Add a `FakeStem` helper (with docs/tests) for capturing enqueued tasks.
- [x] Add `stem_cli` command to list registered tasks with metadata (table + JSON formats).
- [x] Document the new builder/testing utilities and CLI command in READMEs.
- [x] Run `dart format`, `dart analyze`, relevant `dart test`, and `openspec validate enhance-task-ergonomics --strict`.
