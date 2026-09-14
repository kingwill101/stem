---
title: Observability
---

Workflow observability in Stem comes from three layers:

- workflow-aware logs
- store-backed inspection APIs
- dashboard and CLI tooling

## Logs

The internal `stem.workflow.run` task lines carry workflow context. Depending
on the logger and lifecycle event, correlate:

- `workflow`
- `workflowRunId`
- `workflowId`
- `workflowChannel`
- `workflowReason`
- `workflowStep` / checkpoint metadata

The runtime also emits lifecycle logs for enqueue, suspend, fail, and complete.
Treat logs as diagnostic signals rather than the source of truth: retries,
redeliveries, and crashes can produce more than one line for one logical run.

## Store-backed inspection

Use the workflow store for operational queries:

- `listRuns(...)`
- `runsWaitingOn(topic)`
- `get(runId)`

Use the runtime for definition-level inspection:

- `workflowManifest()`

Manifest entries distinguish declared flow `steps` from script
`checkpoints`; use the latter when locating progress for a `WorkflowScript`.

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
consistently across workers. This is transport metadata; it does not make
arbitrary values serializable. For application DTOs, use the same codec and
version on the writer and reader.
