# Changelog

## 0.1.2-wip

- Updated internal package constraints to accept the in-progress `stem`
  prerelease and matching adapter-test prereleases during workspace
  development.

## 0.1.1

- Updated Ormed dependencies to 0.2.0, including the new split
  `ormed_sqlite_core` runtime dependency.
- Simplified SQLite datasource bootstrapping and migration tests to use the new
  Ormed SQLite code-first datasource helpers.
- Removed explicit `ensureSqliteDriverRegistration()` calls from Stem SQLite
  runtime and seed paths by routing config-driven datasource creation through
  the new helper-based bootstrap code.
- Updated the SQLite workflow store to honor caller-provided run ids, keeping
  local workflow runtime metadata/manifests behavior aligned with the shared
  store contract suite.
- Added broker broadcast fan-out support for SQLite routing subscriptions with
  broadcast channels.
- Enabled broadcast fan-out broker contract coverage for the SQLite adapter.
- Wired DataSource and seed runtime initialization to use the shared
  `stemLogger` by default, while still allowing explicit logger injection.
- Hardened datasource/seed configuration overrides to safely merge nullable
  driver options.

## 0.1.0

- Added workflow run lease tracking and claim/renew support so workflows can be
  distributed safely across workers.
- Added DataSource-based factory helpers that run SQLite migrations for
  brokers, result backends, and workflow stores.
- Hardened SQLite connection initialization with file locking/retry to avoid
  concurrent migration/WAL conflicts, and ensured lazy init before
  transactions.
- Migrated the SQLite adapter to Ormed and added a local seed runtime that
  runs seeders without requiring ormed_cli.
- Updated Ormed dependencies to 0.1.0.
- Added workflow run lease migrations, runnable discovery, and offset support
  for workflow listings.
- Migrated IDs to UUID v7, regenerated ORM models, and refreshed datasource
  factories/tests.
- Added workflow store contract tests plus docs/dependency updates.

## 0.1.0-alpha.4

- Added durable watcher tables and atomic event resolution so Durable Workflows
  resume with stored payloads and metadata.
- Auto-versioned checkpoints and rewind logic now align with the core runtime,
  while `saveStep` updates run heartbeats for better ownership tracking.
- Suspension records capture `resumeAt`/`deadline` values sourced from the
  injected workflow clock.
- Published `sqliteWorkflowStoreFactory` so local development and CLI tooling
  can bootstrap SQLite-backed Durable Workflows without external services.

## 0.1.0-alpha.3

- First public alpha release extracted from the core Stem workspace.
