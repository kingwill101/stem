## ADDED Requirements
### Requirement: Core Package Remains Adapter-Agnostic
The `stem` package SHALL expose only platform-agnostic runtime APIs and SHALL NOT depend on
Redis- or Postgres-specific Dart packages.

#### Scenario: Building stem does not require Redis/Postgres SDKs
- **WHEN** an application depends solely on `stem`
- **THEN** `dart pub get` for the app does not download the `redis` or `postgres` packages.

### Requirement: Adapter Packages Provide Redis/Postgres Features
The system SHALL provide Redis and Postgres adapters via dedicated packages that depend on `stem`.

#### Scenario: Redis adapter package
- **WHEN** a developer adds `stem_redis` to their `pubspec`
- **THEN** they can import `RedisStreamsBroker` and related Redis utilities from that package.

#### Scenario: Postgres adapter package
- **WHEN** a developer adds `stem_postgres` to their `pubspec`
- **THEN** they can import `PostgresBroker`, `PostgresResultBackend`, and supporting utilities from
  that package.

### Requirement: CLI Runs Outside Core
The `stem_cli` package SHALL host the CLI entry point and depend on adapter packages for broker
support.

#### Scenario: Installing CLI package
- **WHEN** a developer installs `stem_cli`
- **THEN** running the `stem` CLI connects to Redis/Postgres via the adapter packages without
  requiring the core `stem` package to depend on them directly.
