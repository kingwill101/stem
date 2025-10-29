## Tasks
- [x] Review core/export surface to catalogue Redis/Postgres/CLI code that must migrate.
- [x] Scaffold `packages/stem_redis`, `packages/stem_postgres`, and `packages/stem_cli` with
      workspace-aware pubspecs (including `resolution: workspace`).
- [x] Move Redis adapters (broker, backend, schedulers, revoke store, helper utilities, tests,
      examples, docker helpers) into `stem_redis` and wire exports.
- [x] Move Postgres adapters/backends/schedulers/control code into `stem_postgres` with updated
      imports, tests, and migrations.
- [x] Relocate CLI code (lib + bin) and integration bootstrap scripts into `stem_cli`, updating it to
      depend on `stem`, `stem_redis`, and `stem_postgres`.
- [x] Remove Redis/Postgres code from the core `stem` package, update exports/docs, and adjust its
      dependencies to drop direct Redis/Postgres SDK requirements.
- [x] Update references across the repo (examples, dashboards, docker, tests) to import the new
      packages and ensure all pubspec dependencies are correct.
- [x] Run formatting, `dart analyze`, and relevant `dart test` suites for each package, updating
      tasks when complete.
- [x] Document the new package boundaries (README updates or doc stubs) and ensure the proposal
      checklist reflects completion.
