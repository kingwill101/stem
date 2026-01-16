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
