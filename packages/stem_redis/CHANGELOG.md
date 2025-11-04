## 0.1.0-alpha.4

- Added durable watcher storage and atomic event delivery so Durable Workflows
  resume with persisted payloads and metadata.
- Treat `saveStep` as a heartbeat, auto-version checkpoints in sorted sets, and
  propagate suspension `resumeAt`/`deadline` data across Redis structures.
- Improved queue maintenance by purging priority streams and shutting down claim
  timers when consumers stop, preventing spurious reclaims.

## 0.1.0-alpha.3

- Initial release containing Redis Streams broker, result backend, scheduler
helpers, and contract tests extracted from the core `stem` package.
