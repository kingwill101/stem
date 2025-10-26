## ADDED Requirements
### Requirement: Shared Broker Contract Tests
Stem MUST expose a shared broker contract test suite that adapter packages can invoke to validate core broker behaviour.

#### Scenario: Broker Contract Suite Ensures Ack And DLQ Semantics
- **GIVEN** an adapter provides a factory that creates a `Broker` implementation
- **WHEN** the shared suite runs
- **THEN** it verifies publish → consume → ack/nack flows, delayed delivery, lease expiry recovery, purge behaviour, and dead-letter replay using the provided broker factory.

### Requirement: Shared Result Backend Contract Tests
Stem MUST expose a shared result backend contract test suite that adapter packages can invoke to validate persistence requirements.

#### Scenario: Result Backend Contract Suite Validates Persistence Guarantees
- **GIVEN** an adapter provides a factory that returns a `ResultBackend`
- **WHEN** the shared suite runs
- **THEN** it asserts task status storage, TTL expiry, watcher streams, group aggregation, and worker heartbeat retention semantics using the supplied backend configuration.

### Requirement: Adapter Documentation References Shared Tests
Adapter packages MUST document how to depend on and execute the shared contract suites to guarantee compliance.

#### Scenario: Adapter README Describes Contract Suite Integration
- **GIVEN** a maintainer opens a broker or result backend package README
- **WHEN** the package consumes the shared test suite
- **THEN** the README explains how to run the broker and result backend contract tests as part of local development and CI.
