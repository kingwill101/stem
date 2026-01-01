## Why
Namespace support is inconsistent across adapters (Postgres/SQLite ignore it in multiple stores). We need reliable, cross-adapter scoping so multiple apps/environments can safely share infrastructure.

## What Changes
- Add namespace scoping to all adapters and stores (broker, result backend, workflow, schedule, lock, revoke, heartbeats).
- Persist namespace for SQL adapters and filter all queries by namespace.
- Keep Redis namespace as key prefixing for isolation.
- Add migrations and indexes for namespace columns.
- Add tests that prove namespace isolation across adapters.

## Impact
- Affected specs: namespace-scoping (new)
- Affected code: Postgres/SQLite migrations & models, Redis keying, broker/backend/store queries, tests
- **BREAKING**: Data written without a namespace will be treated as `stem` (default); adapters will now scope reads/writes by namespace.
