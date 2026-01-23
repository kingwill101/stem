## Why
Workflow runs are currently coordinated via in-memory storage, so multiple worker processes cannot share or recover workflow execution state. This blocks horizontal scaling and makes recovery after worker failures unreliable.

## What Changes
- Add a distributed workflow store capability with explicit run claiming/lease semantics.
- Extend workflow runtime/worker orchestration to claim runnable runs from a shared store.
- Implement distributed workflow stores for supported backends (Postgres/Redis) and update in-memory store to match contract.
- Add tests for multi-worker distribution, lease expiry, and recovery.

## Impact
- Affected specs: workflow-store
- Affected code: stem workflow runtime, workflow store implementations, adapter packages
