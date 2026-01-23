## ADDED Requirements

### Requirement: Distributed workflow storage
The system SHALL support a workflow store backed by shared storage so multiple workers can access the same workflow runs.

#### Scenario: Multiple workers share a workflow store
- **GIVEN** two workers configured with the same workflow store
- **WHEN** workflow runs are created
- **THEN** either worker can discover runnable runs from the shared store

### Requirement: Run claiming and leasing
The workflow store SHALL provide run claiming with leases so only one worker executes a run at a time.

#### Scenario: Worker claims a run exclusively
- **GIVEN** a runnable workflow run
- **WHEN** a worker claims the run
- **THEN** other workers cannot claim the same run while the lease is valid

#### Scenario: Lease expiry allows takeover
- **GIVEN** a worker that claimed a run and stops renewing its lease
- **WHEN** the lease expires
- **THEN** another worker can claim the run and continue execution

### Requirement: Lease renewal and release
The workflow store SHALL allow workers to renew or release run leases during execution.

#### Scenario: Worker renews a lease
- **GIVEN** a worker executing a workflow run
- **WHEN** the worker renews the lease
- **THEN** the lease expiration extends without changing ownership

#### Scenario: Worker releases a lease on completion
- **GIVEN** a worker that finishes executing a run
- **WHEN** the worker releases the lease
- **THEN** the run is no longer owned and is not eligible for execution

### Requirement: Runnable run discovery
The workflow store SHALL provide APIs to list runnable runs with optional filters and pagination.

#### Scenario: Worker lists runnable runs
- **GIVEN** runnable workflow runs exist
- **WHEN** a worker queries for runnable runs
- **THEN** the store returns a filtered, paginated list of runnable runs

### Requirement: Gateway workflow store access
The system SHALL expose workflow store operations via the API gateway so workers can coordinate workflow runs across processes.

#### Scenario: Worker claims runs through the gateway
- **GIVEN** a worker connected to the API gateway
- **WHEN** the worker requests runnable runs and claims a lease
- **THEN** the gateway proxies the workflow store operations and enforces lease semantics

### Configuration and operational guidance
Implementations MUST document how lease durations are configured and how they
interact with broker visibility timeouts to avoid stuck runs.

#### Configuration: Run lease controls
- **MUST** allow configuration of the workflow run lease duration (how long a
  worker holds ownership before another worker can claim).
- **MUST** allow configuration of the workflow lease renewal cadence or
  extension duration (how often a worker renews its lease while executing).
- **SHOULD** surface defaults that are safe for typical task durations (e.g.
  lease duration >= broker visibility timeout).

#### Operational guidance: Avoiding stalled runs
- Workers **SHOULD** renew leases before the broker visibility timeout expires.
- If a claim fails because another worker owns the lease, the workflow task
  **SHOULD** be retried to allow takeover once the lease expires.
- Operators **SHOULD** align system clocks (e.g., via NTP) because lease expiry
  is time-based across workers and shared stores.

#### Operational guidance: Failure recovery
- If a worker crashes, another worker **SHALL** be able to claim the run once
  the lease expires.
- Stores **SHOULD** treat expired leases as unowned to enable recovery.
