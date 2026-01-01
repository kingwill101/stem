- [x] Design the workflow DSL facade API (naming, async contract, mapping to
      `FlowBuilder`) and capture the approach in `design.md`.
- [x] Implement the facade in the core runtime, including helpers for `step`,
      `sleep`, `awaitEvent`, and auto-versioned iterations.
- [x] Add unit tests plus adapter contract coverage (via
      `packages/stem_adapter_tests`) exercising the facade through in-memory and
      adapter-backed stores.
- [x] Update documentation and examples so users discover the new facade and
      understand durability rules.
- [x] Run `dart format`, `dart analyze`, full `dart test`, and
      `openspec validate add-workflow-sdk-facade --strict`.
