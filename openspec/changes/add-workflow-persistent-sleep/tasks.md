- [x] Update FlowContext/WorkflowScript helpers so repeated `sleep` calls after a
      wake skip re-suspending when the stored wake timestamp has elapsed.
- [x] Ensure suspension metadata captures `resumeAt` consistently and surface it
      via resume payloads for both Flow and WorkflowScript executions.
- [x] Extend adapter/runtime tests to cover the new persistent sleep behaviour.
- [x] Document the simplified sleep pattern in README/examples.
- [x] Run `dart format`, `dart analyze`, relevant `dart test`, and
      `openspec validate add-workflow-persistent-sleep --strict`.
