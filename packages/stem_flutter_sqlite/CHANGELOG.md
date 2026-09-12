# Changelog

## 0.4.0

- Require Stem `>=0.5.0 <0.6.0`, `stem_flutter >=0.4.0 <0.5.0`, and
  `stem_sqlite >=0.3.0 <0.4.0` for the coordinated release train.

## 0.3.1

- Recover the unpublished 0.3.0 release using the corrected publishing workflow.
  Includes the breaking integration changes listed below.
- Require Stem `>=0.4.2 <0.5.0`, `stem_flutter >=0.3.1 <0.4.0`, and
  `stem_sqlite >=0.2.3 <0.3.0` from the recovery release.

## 0.3.0

- Added real SQLite coverage for core bounded callbacks: persisted batch
  execution, deferred tasks, cancellation, admission deadlines, and reopening.
- Added `StemFlutterSqlite.createApp`, returning a real core `StemApp` backed by
  managed local stores, with one `StemFlutterSqliteConfig` for storage settings.
- Required Stem `>=0.4.1 <0.5.0`, `stem_flutter >=0.3.0 <0.4.0`, and
  `stem_sqlite >=0.2.2 <0.3.0` for the shared application surface and safe
  consumer teardown.
- Re-exported Flutter and stable Stem APIs for ordinary task/module usage.
- **Breaking:** Removed the legacy producer runtime, worker launcher, worker
  stores, and bootstrap payload. Core `StemApp` owns execution and store
  lifecycles.
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
