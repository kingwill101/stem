# Changelog

## 0.1.2-wip

- Updated internal package constraints to accept the in-progress `stem`
  prerelease and matching adapter-test prereleases during workspace
  development.

## 0.1.1

- Updated the Redis workflow store to honor caller-provided run ids, matching
  the runtime metadata/manifests contract used by the core workflow views.
- Rejected duplicate caller-provided workflow run ids atomically so existing
  run and checkpoint state is preserved on collisions.
- Enabled broadcast fan-out broker contract coverage in Redis integration tests
  by wiring additional broker instances for shared-namespace fan-out checks.

## 0.1.0

- Added workflow run lease tracking and claim/renew helpers to distribute
  workflow execution safely across workers.
- Maintenance updates to adapter tooling and formatting (no runtime changes).
- Added Redis workflow store support with runnable discovery and metadata
  paging improvements.
- Migrated IDs to UUID v7 and updated datasource handling.
- Added workflow store contract tests and refreshed dependencies/docs.

## 0.1.0-alpha.4

- Added durable watcher storage and atomic event delivery so Durable Workflows
  resume with persisted payloads and metadata.
- Treat `saveStep` as a heartbeat, auto-version checkpoints in sorted sets, and
  propagate suspension `resumeAt`/`deadline` data across Redis structures.
- Improved queue maintenance by purging priority streams and shutting down claim
  timers when consumers stop, preventing spurious reclaims.
- Published `redisWorkflowStoreFactory` so CLI tooling and integration tests can
  spin up Redis-backed Durable Workflow stores with one helper.
- Added lock-store contract coverage for `RedisLockStore`, validating the
  semantics required by `TaskOptions.unique` and scheduler coordination.

## 0.1.0-alpha.3

- Initial release containing Redis Streams broker, result backend, scheduler
helpers, and contract tests extracted from the core `stem` package.
