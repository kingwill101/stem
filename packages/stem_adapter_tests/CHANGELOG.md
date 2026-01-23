## Unreleased

- Split lock/workflow store contract suites and expanded runnable discovery
  coverage.
- Updated dependencies and analysis options.

## 0.1.0-dev

- Added workflow store contract coverage for run leasing and runnable run
  discovery.
- Expanded contract coverage for typed result encoders and payload encoders
  (including TaskResultEncoder) used by adapters.

## 0.1.0-alpha.4

- Hardened the contract suite around the new **Durable Workflows** API surface:
  auto-versioned checkpoints, suspension metadata, and watcher payload delivery.
- Contract harness now injects a shared `FakeWorkflowClock` into runtimes and
  stores, eliminating reliance on real time during adapter tests.
- Added a dedicated lock-store contract suite so adapters can verify their
  `LockStore` implementations meet the semantics needed by unique tasks and
  scheduler coordination.
- Expanded broker contract coverage with optional priority ordering and
  broadcast fan-out scenarios to keep routing guarantees consistent across
  implementations.

## 0.1.0-alpha.3

- Initial release extracted from the core `stem` package providing shared broker
  and result-backend contract test suites for adapters.
