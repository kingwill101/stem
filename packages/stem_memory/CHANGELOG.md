# Changelog

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
