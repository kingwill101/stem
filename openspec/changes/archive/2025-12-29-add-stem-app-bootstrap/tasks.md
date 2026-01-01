## Implementation Tasks

- [x] Define core factory abstractions (`StemBrokerFactory`, `StemBackendFactory`, `WorkflowStoreFactory`, etc.) and implement `StemApp` lifecycle management using in-memory defaults.
- [x] Layer `StemWorkflowApp` on top of `StemApp`, providing convenience APIs for registering workflows and running them.
- [x] Add adapter-side factory extensions in `stem_redis`, `stem_postgres`, and `stem_sqlite` to produce their respective brokers/backends/workflow stores.
- [x] Update examples/tests to rely on the new helpers and document the streamlined workflow setup.
- [x] Run `dart format`, `dart analyze`, affected `dart test`, and `openspec validate add-stem-app-bootstrap --strict`.
