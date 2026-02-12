## 0.1.1

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
