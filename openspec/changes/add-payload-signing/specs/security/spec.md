## ADDED Requirements

### Requirement: Cryptographic Key Management
Stem security guidance MUST include operational procedures for signing key lifecycle management.
#### Scenario: Key rotation runbook published
- **GIVEN** an operator prepares to rotate signing keys
- **WHEN** they consult the operations guide
- **THEN** the guide MUST describe preparation, rollout, validation, and rollback steps
- **AND** it MUST specify how to update environment variables/secrets across enqueuers and workers

### Requirement: TLS Automation & Vulnerability Scanning
Stem MUST offer automation and documentation to secure transport and detect known vulnerabilities.
#### Scenario: TLS bootstrap scripts available
- **GIVEN** a user adopts the examples or production deployment
- **WHEN** they follow the security instructions
- **THEN** they MUST be able to provision certificates for Redis and HTTP endpoints using the provided scripts or Terraform snippets
- **AND** the services MUST refuse plaintext connections when TLS is enabled

#### Scenario: Recurring vulnerability scan documented
- **GIVEN** a maintainer is responsible for security hygiene
- **WHEN** they run the documented scanning workflow (CI job or scheduled script)
- **THEN** findings MUST be reported to the team and tracked until closure
- **AND** the process MUST specify cadence, tooling, and escalation paths
