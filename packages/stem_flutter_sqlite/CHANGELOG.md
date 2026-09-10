# Changelog

## Unreleased

- Added real SQLite coverage for core bounded callbacks: persisted batch
  execution, deferred tasks, cancellation, admission deadlines, and reopening.
- Added `StemFlutterSqlite.createApp`, returning a real core `StemApp` backed by
  managed local stores, with one `StemFlutterSqliteConfig` for storage settings.
- Required the Stem 0.4 API line for the shared application surface.
- Re-exported Flutter and stable Stem APIs for ordinary task/module usage.
- Removed the legacy producer runtime, worker launcher, worker stores, and
  bootstrap payload. Core `StemApp` owns execution and store lifecycles.
- Reuse core factories for manually supplied stores and Ormed data sources.
- Moved required Flutter/Ormed dependency setup here from `stem_flutter`.
  `createApp` initializes it automatically; manual integrations can call
  `StemFlutterSqlite.initialize`.
- Reject path traversal in application directory and helper file names; explicit
  layouts remain available for custom paths.
- Migrated the mobile example and documentation away from manual worker protocols.

## 0.2.1

- Widened Stem compatibility to include the 0.4 portable runtime line.
- Updated the Flutter SQLite integration for the Stem 0.3.0 adapter line and
  Dart 3.12 minimum.
- Updated the Flutter SQLite integration for the Stem 0.3.0 adapter line.

## 0.1.0

- Initial Flutter SQLite adapter helpers for Stem.
