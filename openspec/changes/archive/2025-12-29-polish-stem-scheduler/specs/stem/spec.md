## MODIFIED Requirements

### Requirement: Scheduler (Beat) Operations
The scheduler MUST expose operational tooling and locking guarantees so periodic jobs execute precisely once with full visibility.
#### Scenario: Schedule metadata exposed via CLI
- **GIVEN** schedules are stored in the Redis schedule store
- **WHEN** an operator runs `stem schedule list`
- **THEN** the CLI MUST show id, task, cron/interval, next run timestamp, last run timestamp, jitter, and enabled status sourced from the schedule store

#### Scenario: Distributed lock prevents double fire with renewal
- **GIVEN** two Beat instances evaluate due entries concurrently
- **WHEN** one instance acquires the per-entry lock and begins enqueueing the task
- **THEN** it MUST renew the lock before TTL expiration until the task is enqueued and metadata updated
- **AND** the other instance MUST observe the lock, skip execution, and record a contention metric

#### Scenario: Dry-run validates schedule definition
- **GIVEN** an operator invokes `stem schedule dry-run cleanup --count 3`
- **WHEN** the command evaluates the entry
- **THEN** Stem MUST output the next three run timestamps including jitter adjustments and refuse execution if the schedule fails validation (invalid cron/interval out of range)
