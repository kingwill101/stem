## Implementation Tasks

- [x] Survey current usages of `TaskOptions.unique` / `uniqueFor` and document expected dedupe key inputs.
- [x] Design and land a shared `UniqueTaskCoordinator` abstraction backed by `LockStore` with deterministic key derivation and TTL handling.
- [x] Update `Stem.enqueue` (and any other enqueue helpers) to consult the coordinator before publishing and to short-circuit duplicates.
- [x] Ensure workers release dedupe locks when tasks reach a terminal state, including failures and cancellations.
- [x] Emit metrics/signals and result-backend metadata when a duplicate enqueue is skipped.
- [x] Add unit tests for coordinator logic and worker unlock behaviour plus an integration test using the Redis lock store.
- [x] Refresh developer docs / README to explain enabling unique tasks and operational caveats.
- [x] Run `dart format`, `dart analyze`, `dart test`, and `openspec validate add-task-deduplication --strict`.
