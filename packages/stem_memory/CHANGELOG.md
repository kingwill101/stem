## 0.1.0

- Added `stem_memory` package with in-memory adapter exports and factory
  helpers.
- Added shared adapter contract coverage (broker/backend/workflow/lock) for the
  in-memory adapter using `stem_adapter_tests`.
- Improved in-memory adapter contract parity and capability coverage, including
  explicit skip reporting for unsupported checks.
