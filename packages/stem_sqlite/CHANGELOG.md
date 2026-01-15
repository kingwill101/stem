## 0.1.0-dev

- Added DataSource-based factory helpers that run SQLite migrations for
  brokers, result backends, and workflow stores.
- Hardened SQLite connection initialization with file locking/retry to avoid
  concurrent migration/WAL conflicts, and ensured lazy init before
  transactions.
- Migrated the SQLite adapter to Ormed and added a local seed runtime that
  runs seeders without requiring ormed_cli.
- Updated Ormed dependencies to 0.1.0-dev+6.

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
