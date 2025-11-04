## 0.1.0-alpha.4

- Added durable watcher persistence and atomic event resolution so Durable
  Workflows resume with stored payloads and metadata.
- Refreshed workflow run bookkeeping: `saveStep` now acts as a heartbeat,
  rewind/auto-version checkpoints are persisted with accurate ordering, and
  suspension records track `resumeAt`/`deadline`.
- Implemented chord-claiming improvements and claim-timer cleanup to keep
  Postgres queues healthy during purges and consumer shutdown.

## 0.1.0-alpha.3

- Initial release containing Postgres broker, result backend, scheduler stores,
and adapter contract tests extracted from the core `stem` package.
