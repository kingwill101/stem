---
title: Observability
---

Workflow observability in Stem comes from three layers:

- workflow-aware logs
- store-backed inspection APIs
- dashboard and CLI tooling

## Logs

Recent logging improvements add workflow context onto the internal
`stem.workflow.run` task lines. You can now correlate:

- `workflow`
- `workflowRunId`
- `workflowId`
- `workflowChannel`
- `workflowReason`
- `workflowStep` / checkpoint metadata

The runtime also emits lifecycle logs for enqueue, suspend, fail, and complete.

## Store-backed inspection

Use the workflow store for operational queries:

- `listRuns(...)`
- `runsWaitingOn(topic)`
- `get(runId)`

Use the runtime for definition-level inspection:

- `workflowManifest()`

## Dashboard and CLI

The dashboard uses the same store/manifests to surface:

- registered workflows
- run status
- current step/checkpoint
- worker health
- queue and DLQ state around workflow-driven tasks

CLI integrations rely on the same persisted state, so keeping the workflow
store healthy is what keeps the tools responsive.

## Encoders and result metadata

Workflow runs inherit Stem payload encoder behavior. Result encoder ids are
persisted in `RunState.resultMeta`, which lets tooling decode stored outputs
consistently across workers.
