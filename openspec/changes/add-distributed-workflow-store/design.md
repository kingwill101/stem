## Context
Workflow execution currently relies on an in-memory workflow store, which prevents multiple workers from sharing ownership of runnable workflow runs. A distributed store is required to claim, lease, and resume runs safely across processes.

## Goals / Non-Goals
- Goals:
  - Persist workflow runs in a shared store that multiple workers can access.
  - Provide run claiming/lease semantics so only one worker executes a run at a time.
  - Allow recovery when a worker crashes or stops renewing its lease.
  - Keep in-memory store behavior compatible for local development.
- Non-Goals:
  - Exactly-once workflow execution guarantees.
  - Cross-region replication or multi-master consensus.

## Decisions
- Introduce explicit run ownership and lease fields in workflow run storage.
- Add workflow store APIs for listing runnable runs, claiming with leases, renewing leases, and releasing ownership.
- Implement backend-specific lease cleanup (sweeper/TTL) to allow re-claim after expiry.
- Update workflow runtime to poll/claim runs from the shared store instead of relying on local memory.

## Risks / Trade-offs
- Lease tuning impacts throughput and recovery time.
  - Mitigation: configurable lease duration and renewal interval.
- Additional database load from polling/claiming.
  - Mitigation: backoff when no work and batch claim support.

## Migration Plan
- Add new fields/migrations for workflow run ownership and lease metadata.
- Update adapters to populate and honor ownership/lease fields.
- Update runtime to use claim/renew/release flow.
- Maintain compatibility with existing in-memory behavior for single-process deployments.

## Open Questions
- Should claim operations support batching and priority ordering?
- Do we need a separate coordinator for workflow polling vs worker execution?
