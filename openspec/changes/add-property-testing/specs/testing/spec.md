## ADDED Requirements

### Requirement: Property-based testing for core invariants
The system SHALL include property-based tests for core Stem invariants, including enqueue/execute correctness, retry semantics, and schedule monotonicity.

#### Scenario: Core invariants are exercised
- **WHEN** property tests run for Stem core
- **THEN** randomized inputs validate invariants across enqueue, execution, retries, and schedules

### Requirement: Chaos scenarios in package test suites
The system SHALL include chaos scenarios inside test suites for Stem and Stem Cloud Gateway to validate robustness under failures.

#### Scenario: Chaos runners execute in tests
- **WHEN** chaos-enabled tests run
- **THEN** the suites execute failure scenarios without external tooling

### Requirement: Per-package test helpers
The system SHALL provide per-package property/chaos test helpers so each package can define generators and invariants locally.

#### Scenario: Package helpers are available
- **WHEN** tests are authored in stem or stem_cloud_gateway
- **THEN** local helpers exist for property/chaos test setup
