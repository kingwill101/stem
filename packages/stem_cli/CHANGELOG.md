## 0.1.0

- Updated CLI adapter wiring and docker test stack to the Ormed-backed
  integrations.
- Added workflow agent help output to document required configuration.

## Unreleased

- Added cloud configuration helpers and revoke-store factory wiring.
- Improved auth token handling in CLI utilities and expanded tests.
- Updated README/Justfile guidance and refreshed dependencies.

## 0.1.0-alpha.4

- Introduced the `stem wf` command group for starting runs, listing history and
  suspended waiters, showing checkpoints, cancelling/rewinding, and emitting
  events so operators can drive Durable Workflows end-to-end from the CLI.
- Added `stem tasks ls` to print registered task metadata (description, tags,
  idempotency) or emit JSON for automation, making registries auditable before
  deploys.
- Extended `stem health` to probe Postgres result backends alongside Redis,
  surfacing backend-specific diagnostics.
- Aligned dependencies with the workflow clock release so `stem test` and the
  docker-backed suites exercise deterministic runtime stores.

## 0.1.0-alpha.3

- Initial release after extracting CLI tooling from the core `stem` package.
- Provides `stem` command with support for Redis/Postgres adapters and dockerised
test stack.
