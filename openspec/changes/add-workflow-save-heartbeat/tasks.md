- [x] Document lease heartbeat expectation in `WorkflowStore` contract and expose
      the timestamp via `RunState`.
- [x] Refresh heartbeat in each store (in-memory, Postgres, Redis, SQLite) when
      `saveStep` commits and ensure the update is atomic with the checkpoint.
- [x] Wire the runtime so every successful `saveStep` (Flow + Script) persists
      the heartbeat and propagates it to consumers.
- [x] Extend adapter contract tests and runtime integration tests to cover the
      heartbeat semantics.
- [x] Update docs/examples to highlight the checkpoint heartbeat and run
      formatting/analyze/tests plus `openspec validate add-workflow-save-heartbeat --strict`.
