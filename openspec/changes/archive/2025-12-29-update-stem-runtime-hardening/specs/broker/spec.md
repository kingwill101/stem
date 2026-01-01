## ADDED Requirements

### Requirement: Queue Purge Integrity
Redis-backed brokers MUST treat queue purges as a holistic operation that clears all priority stream variants and associated delayed buckets so no pending deliveries survive the purge call.

#### Scenario: Purge removes priority streams
- **GIVEN** a queue has messages across its base stream and priority-prefixed streams
- **WHEN** `purge(queue)` is invoked
- **THEN** the broker MUST delete every stream key participating in that queue (including priority variants) and confirm `pendingCount(queue)` returns zero

#### Scenario: Purge removes consumer groups
- **GIVEN** consumer groups exist for the queue’s priority streams
- **WHEN** `purge(queue)` runs
- **THEN** the broker MUST drop the groups or recreate them lazily so subsequent consumers encounter a fresh stream without stale pending entries

### Requirement: Claim Timer Teardown
Background claim loops that recover abandoned deliveries MUST stop when the associated subscription is cancelled so idle brokers do not continue issuing Redis commands indefinitely.

#### Scenario: Cancelled subscription stops claim timers
- **GIVEN** a worker subscribes to a queue and then disposes the stream controller
- **WHEN** the worker cancels the subscription
- **THEN** the broker MUST cancel any claim timers spawned for that consumer within the grace period and cease issuing `XAUTOCLAIM/XCLAIM` requests for that subscription
