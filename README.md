# Stem

This repository hosts the Stem background job platform and its related packages.

## Packages

- **`packages/stem`** – Core runtime (contracts, worker, in-memory adapters, scheduler, signals).
- **`packages/stem_cli`** – Command-line tooling (`stem` executable), dockerised test stack, and CLI utilities.
- **`packages/stem_redis`** – Redis Streams broker, result backend, watchdog helpers, and contract tests.
- **`packages/stem_postgres`** – Postgres broker, result backend, scheduler stores, and contract tests.
- **`packages/stem_sqlite`** – SQLite broker/result backend (local development/testing).
- **`packages/dashboard`** – Hotwire-based operations dashboard (experimental).
- **`packages/stem_adapter_tests`** – Shared contract suites for adapter implementations.

Each package maintains its own README with installation and usage details. The
root workspace is organised as a Dart `workspace` (see `pubspec.yaml`) to allow
cross-package development and testing.

## Development

1. Install Dart 3.9 or newer (`dart --version`).
2. Pull dependencies:
   ```bash
   dart pub get
   ```
3. Run the quality gates:
   ```bash
   dart format --output=none --set-exit-if-changed .
   dart analyze
   dart test packages/stem
   ```
4. Adapter and CLI integration tests require the dockerised stack:
   ```bash
   source packages/stem_cli/_init_test_env
   dart test packages/stem_redis
   dart test packages/stem_postgres
   dart test packages/stem_cli
   ```


### Licensing & Funding

- Licensed under MIT (see `LICENSE`).
- Support development via [Buy Me A Coffee](https://www.buymeacoffee.com/kingwill101).

