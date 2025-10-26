## 1. Planning & Schema
- [x] 1.1 Add migration helpers that create SQLite tables (jobs, dead letters, results, groups, heartbeats) with required indices.
- [x] 1.2 Document operational settings (WAL, synchronous) in code comments and developer docs.

## 2. Broker Implementation
- [ ] 2.1 Implement `SqliteConnections` to manage shared database access with transactional helpers.
- [ ] 2.2 Add `SqliteBroker` covering publish, consume, ack/nack, lease extension, purge, and dead-letter APIs.
- [ ] 2.3 Add sweeper logic to reclaim expired locks and prune DLQ rows.
- [ ] 2.4 Write unit/integration tests for enqueue → consume → ack/nack, retries, and DLQ replay.

## 3. Result Backend Implementation
- [ ] 3.1 Implement `SqliteResultBackend` mirroring the Postgres backend (store, fetch, watch, group, heartbeat APIs).
- [ ] 3.2 Add cleanup routines for TTL expirations and test coverage for groups/heartbeats.

## 4. Dashboard & Tooling
- [ ] 4.1 Introduce `SqliteDashboardService` plus CLI flag to point the dashboard at a `.db` file.
- [ ] 4.2 Render queue/worker metrics using SQLite aggregates and add smoke tests for the service.

## 5. Validation
- [ ] 5.1 Run `dart format`, `dart analyze`, targeted `dart test` suites, and `openspec validate add-sqlite-broker-backend --strict`.
