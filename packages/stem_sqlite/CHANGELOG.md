## 0.1.0-alpha.4

- Added durable watcher tables and atomic event resolution so Durable Workflows
  resume with stored payloads and metadata.
- Auto-versioned checkpoints and rewind logic now align with the core runtime,
  while `saveStep` updates run heartbeats for better ownership tracking.
- Suspension records capture `resumeAt`/`deadline` values sourced from the
  injected workflow clock.

## 0.1.0-alpha.3

- First public alpha release extracted from the core Stem workspace.
