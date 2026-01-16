## 0.1.0-dev

- Added workflow run lease tracking and claim/renew helpers to distribute
  workflow execution safely across workers.
- Fixed worker heartbeat lookups by restoring soft-deleted heartbeat rows on
  upsert.
- Added DataSource-based initialization that runs migrations before use, and
  introduced async `fromDataSource` helpers across Postgres adapters (including
  workflow stores).
- Migrated the Postgres adapter to Ormed with generated registry/migrations for
  schema management.
- Added a local seed runtime to run Postgres seeders without requiring
  ormed_cli.
- Hardened lock-store timing/TTL evaluation for more reliable coordination.
- Updated Ormed dependencies to 0.1.0-dev+6.

## 0.1.0-alpha.4

- Added durable watcher persistence and atomic event resolution so Durable
  Workflows resume with stored payloads and metadata.
- Refreshed workflow run bookkeeping: `saveStep` now acts as a heartbeat,
  rewind/auto-version checkpoints are persisted with accurate ordering, and
  suspension records track `resumeAt`/`deadline`.
- Implemented chord-claiming improvements and claim-timer cleanup to keep
  Postgres queues healthy during purges and consumer shutdown.
- Shipped `postgresWorkflowStoreFactory` so CLI tooling and integration tests
  can bootstrap Postgres-backed Durable Workflows with a single helper.
- Added lock-store contract coverage for `PostgresLockStore`, ensuring the
  semantics required by `TaskOptions.unique` and scheduler coordination stay
  portable across adapters.

## 0.1.0-alpha.3

- Initial release containing Postgres broker, result backend, scheduler stores,
and adapter contract tests extracted from the core `stem` package.
