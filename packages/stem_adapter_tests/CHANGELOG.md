## 0.1.0-alpha.4

- Hardened the contract suite around the new **Durable Workflows** API surface:
  auto-versioned checkpoints, suspension metadata, and watcher payload delivery.
- Contract harness now injects a shared `FakeWorkflowClock` into runtimes and
  stores, eliminating reliance on real time during adapter tests.

## 0.1.0-alpha.3

- Initial release extracted from the core `stem` package providing shared broker
  and result-backend contract test suites for adapters.
