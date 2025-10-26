## ADDED Requirements
### Requirement: SQLite Broker Provides Queue Operations
Stem MUST offer a `SqliteBroker` that satisfies the existing broker contract so applications can run without external queue infrastructure.

#### Scenario: Publish And Consume From SQLite
- **GIVEN** an application opens a SQLite database file with the Stem broker factory
- **WHEN** it publishes an envelope to queue `default`
- **AND** a worker subscribes to the same queue via `SqliteBroker.consume`
- **THEN** the worker receives the envelope payload exactly once per successful `ack`
- **AND** the broker stores the job in `stem_queue_jobs` with priority ordering.

### Requirement: SQLite Broker Manages Leases
The SQLite broker MUST guard concurrency through short-lived leases so competing workers do not process the same job simultaneously.

#### Scenario: Expired Lease Is Requeued
- **GIVEN** a job is locked by worker A with `locked_until` set in the past
- **WHEN** the lock sweeper runs
- **THEN** the broker clears the lock fields
- **AND** the job becomes visible to another worker on the next consume loop.

### Requirement: SQLite Broker Handles Dead Letters
Failures in the SQLite broker MUST be storable, inspectable, and replayable via the Dead Letter Queue APIs.

#### Scenario: Negative Acknowledgement Without Requeue
- **GIVEN** a worker calls `nack` with `requeue=false`
- **WHEN** the broker processes the request
- **THEN** the job row is deleted from `stem_queue_jobs`
- **AND** an entry with the same envelope id is inserted into `stem_dead_letters`
- **AND** `listDeadLetters` returns that entry with its failure metadata.
