## MODIFIED Requirements

### Requirement: Security & Integrity
Stem MUST provide mechanisms to protect task payloads against tampering in transit or at rest.
#### Scenario: Signed payloads rejected when verification fails
- **GIVEN** payload signing is enabled for an environment
- **WHEN** a worker dequeues a task whose signature is missing or invalid
- **THEN** the worker MUST reject the task without executing the handler
- **AND** it MUST emit a security audit metric/log entry identifying the failure
- **AND** the task MUST be moved to the dead-letter queue with the failure reason preserved

#### Scenario: Key rotation without downtime
- **GIVEN** operators rotate signing keys
- **WHEN** new tasks are enqueued using the new key while existing workers still accept the previous key
- **THEN** the system MUST allow a configurable overlap period where multiple keys are accepted
- **AND** documentation MUST describe the rotation process and blast radius
