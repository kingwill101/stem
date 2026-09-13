# Changelog

## 0.3.0

- Join same-data-source transactions without nested queue deadlocks. Drain
  admitted operations before commit and make any admitted failure rollback-only,
  including caught failures. Bind outbox publications to their originating
  transaction scope and reject retained or escaped writes after it closes.
- Add workflow journal persistence with run-row locking, record revision CAS,
  atomic checkpoint/compensation writes, and ordered cleanup recovery.
- Add atomic first-terminal-wins completion/cancellation and prevent ordinary
  workflow mutations from resurrecting terminal runs.
- Classify fenced workflow failure outcomes inside the same row-locked
  transaction as the mutation. Verify competing terminal failures across
  independently opened stores have one applied outcome.
- Add the additive workflow execution-fencing migration (`execution_id`) and
  fenced lease/failure operations. Apply the migration before using mixed
  workers or relying on stale-execution protection; `terminal: false` records
  error metadata without ending the run, while terminal failure is conditional
  on the captured execution identity.
- Require Stem `>=0.5.0 <1.0.0` and the shared adapter contract
  `>=0.3.0 <1.0.0`, allowing later pre-1.0 releases.

## 0.2.1

- Widened Stem compatibility to include the 0.4 portable runtime line.
- Raised the minimum Dart SDK to 3.12.0 and the Ormed dependencies to 0.3.0.
- Retained generated model definitions for Stem's internal typed repositories;
  Ormed's codegen-free database facade remains available for application-side
  ad-hoc access.
- Datasource logger injection now uses Stem's dependency-neutral `StemLogger`
  facade; the Ormed contextual logger remains an adapter implementation detail.
- Added conditional terminal-result updates so late completion attempts cannot
  overwrite an existing terminal state.
- Updated the Postgres adapter for Stem 0.3.0 and the capability-aware broker
  contract.
- Added the transactional outbox, distributed rate limiter, migration registry,
  and historical upgrade coverage.
- Added durable PostgreSQL lock fencing tokens with an additive migration and
  row-locked acquisition semantics.
- Historical upgrade coverage verifies that current lock acquisition respects
  active legacy-schema locks before taking over only after expiry.

## 0.1.3

- Removed the prerelease core dependency range from the published-package
  manifest.
- Added a PostgreSQL-backed distributed token-bucket `PostgresRateLimiter`
  with server-clock refill and transactional row locking.
- Transactional outbox wrapping and relay now accept the narrow `QueueBroker`
  contract, so queue-only adapters do not need to implement legacy inspection
  and dead-letter methods.

## 0.1.2

- Added a PostgreSQL transactional outbox for atomic application writes and
  task publication records, with leased at-least-once dispatch.

## 0.1.1

- Updated Ormed dependencies to 0.2.0 for the Postgres adapter stack.
- Simplified explicit Postgres URL datasource bootstrapping to use the new
  Ormed code-first datasource helper path.
- Removed explicit `ensurePostgresDriverRegistration()` calls from Stem
  Postgres runtime and seed paths by routing config-driven datasource creation
  through the new helper-based bootstrap code.
- Updated Postgres workflow stores to honor caller-provided run ids, keeping
  adapter behavior aligned with workflow runtime metadata/manifests and the
  shared workflow-store contract suite.

## 0.1.0

- Normalized `postgresResultBackendFactory` to accept a positional `uri`
  argument, matching the adapter factory style used across packages.
- Updated Postgres adapter wiring to use the new factory signature.
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
- Updated Ormed dependencies to 0.1.0.
- Added workflow run lease migrations plus runnable discovery and metadata
  paging updates in the workflow store.
- Migrated IDs to UUID v7 and simplified datasource/connection handling.
- Added workflow store contract coverage and refreshed adapter docs/tests.
- Updated dependencies.
- Wired DataSource and seed runtime initialization to use the shared
  `stemLogger` by default, while still allowing explicit logger injection.
- Hardened datasource/seed configuration overrides to safely merge nullable
  driver options.

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
