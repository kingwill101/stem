# Changelog

## Unreleased

- Documented core `StemApp.runUntilIdle` for app-owned background callbacks,
  including admission deadlines, safe draining, outcome mapping, and OS limits.
- Added `StemFlutter.createApp`, returning the ordinary core `StemApp` with
  Flutter initialization and local-worker defaults; re-exported the stable API.
- Required the Stem 0.4 API line for the shared application surface.
- Removed the Flutter queue monitor, snapshot/tracked-job models, custom worker
  host, and worker signal/status protocol. Use existing core Stem APIs instead.
- Removed TimeMachine initialization and its dependency from the adapter-neutral
  package. Required Ormed dependency setup now lives in `stem_flutter_sqlite`.
- Removed binary asset payload helpers for the custom worker-isolate protocol.
- Kept debug presentation in the example rather than the integration package.
- Replaced manual isolate setup with standard Stem task APIs.

## 0.2.1

- Widened Stem compatibility to include the 0.4 portable runtime line.
- Updated the Flutter integration for the Stem 0.3.0 release train and Dart
  3.12 minimum.
- Updated the Flutter integration for Stem 0.3.0 and explicit worker startup.

## 0.1.0

- Initial Flutter integration package for Stem.
- Added storage path helpers, TimeMachine bootstrapping, worker isolate hosting,
  and queue monitoring primitives.
