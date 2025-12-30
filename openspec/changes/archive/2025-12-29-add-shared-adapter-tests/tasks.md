## Tasks
- [x] Audit existing broker and result backend tests to enumerate contract expectations that the shared suite must cover.
- [x] Scaffold a `stem_adapter_tests` (name TBD) package exporting broker and backend compliance harnesses with adapter factories and configurable hooks.
- [x] Port current Redis/Postgres baseline tests into the shared harness, ensuring they rely only on public contracts.
- [x] Integrate the shared tests into Redis/Postgres and SQLite packages, removing redundant bespoke cases.
- [x] Document usage in package READMEs and run `dart format`, `dart analyze`, and `dart test` across all affected packages.
- [x] Validate specs with `openspec validate add-shared-adapter-tests --strict`.
