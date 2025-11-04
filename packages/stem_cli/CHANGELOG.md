## 0.1.0-alpha.4

- Added durable workflow introspection commands (runs, watchers, cancellations)
  so the CLI surfaces the new runtime metadata powering Durable Workflows.
- Extended `stem health` to probe Postgres result backends alongside Redis,
  surfacing backend-specific diagnostics.
- Aligned dependencies with the workflow clock release so `stem test` and the
  docker-backed suites exercise deterministic runtime stores.

## 0.1.0-alpha.3

- Initial release after extracting CLI tooling from the core `stem` package.
- Provides `stem` command with support for Redis/Postgres adapters and dockerised
test stack.
