# Changelog

## 0.3.0

- Require Dart `>=3.13.0 <4.0.0`.
- Support the core workflow journal and complete in-memory run-change feed used
  by reactive host observation.
- The re-exported in-memory workflow store supports atomic first-terminal-wins
  completion/cancellation and preserves terminal outcomes.
- Require Stem `>=0.5.0 <1.0.0` and the shared adapter contract
  `>=0.3.0 <1.0.0`, allowing later pre-1.0 releases.

## 0.2.1

- Widened Stem compatibility to include the 0.4 portable runtime line.
- Updated the in-memory adapter for the Stem 0.3.0 release train and Dart 3.12
  minimum.
- Updated the compatibility package for Stem 0.3.0 and the core-owned memory
  entrypoint.

## 0.1.2

- Kept the compatibility package aligned with the core-owned
  `package:stem/memory.dart` implementation after the adapter layering fix.

## 0.1.1

- Made the package an explicit compatibility export for
  `package:stem/memory.dart`.
- Raised the minimum Stem version so the package cannot resolve against a
  published core artifact that does not expose the memory library.

## 0.1.0

- Updated the in-memory workflow store to honor caller-provided run ids,
  aligning it with workflow runtime metadata views and manifest tooling.
- Rejected duplicate caller-provided workflow run ids instead of overwriting
  existing run/checkpoint state.
- Renamed `memoryBackendFactory` to `memoryResultBackendFactory` for adapter
  factory naming consistency.
- Updated docs and exports to use `StemClient`-first examples and the renamed
  result backend factory.
- Added `stem_memory` package with in-memory adapter exports and factory
  helpers.
- Added shared adapter contract coverage (broker/backend/workflow/lock) for the
  in-memory adapter using `stem_adapter_tests`.
- Improved in-memory adapter contract parity and capability coverage, including
  explicit skip reporting for unsupported checks.
