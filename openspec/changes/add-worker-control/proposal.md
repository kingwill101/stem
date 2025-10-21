## Why
- Celery’s worker guide highlights operational capabilities (remote control/inspection, autoscaling, lifecycle controls) that Stem lacks, blocking migrations and day-2 operations.
- Stem workers run with fixed concurrency, no remote telemetry channel, and limited shutdown semantics, making it hard to manage clusters or recover from hot spots.
- Operators expect to revoke tasks, inspect inflight work, or adjust concurrency without restarting, but current tooling cannot deliver this.

## What Changes
- Introduce a bi-directional worker control channel so operators (via CLI or API) can ping, inspect, revoke, and update workers at runtime.
- Add autoscaling hooks that adjust worker concurrency within configured bounds based on queue depth/inflight metrics.
- Expand worker lifecycle management with configurable warm/soft/hard shutdown behaviours, per-task recycle thresholds, and memory guards.
- Document and expose these capabilities through the Stem CLI to match Celery’s worker UX.

## Impact
- Requires protocol additions between coordinator and workers (control messages, heartbeats) and storage for persistent revokes.
- Worker runtime and CLI will gain new options; existing deployments must opt-in to autoscaling/features to preserve current behaviour.
- Additional monitoring/telemetry will be needed to support autoscaling decisions and remote inspection.
