# Changelog

## Unreleased

## 0.3.0

- Updated the CLI and adapter dependencies for the Stem 0.4.0 release train
  and Dart 3.12 minimum.
- Hardened Redis TLS integration fixtures so private keys remain owner-only
  while test containers run as the non-root Redis user.

## 0.2.0

- Updated CLI adapter dependencies for the Stem 0.3.0 release train.
- Kept worker startup explicit and retained `schedule trigger` support.
- Made Docker-backed integration setup reuse disposable TLS assets and wait for
  Redis/Postgres health before exporting test endpoints.

## 0.1.2

- Added `stem schedule trigger` for one-off execution without mutating the
  persisted recurring schedule.
- Hardened CLI integration discovery and documented explicit worker startup.
- Removed the prerelease core dependency range from the published-package
  manifest.

## 0.1.0

- Updated CLI adapter wiring and docker test stack to the Ormed-backed
  integrations.
- Added workflow agent help output to document required configuration.
- Added cloud configuration helpers and revoke-store factory wiring.
- Improved auth token handling in CLI utilities and expanded tests.
- Updated README/Taskfile guidance and refreshed dependencies.

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
