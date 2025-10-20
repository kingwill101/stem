## MODIFIED Requirements

### Requirement: Chaos Testing Coverage
Stem MUST exercise chaos scenarios against both in-memory and real Redis brokers to validate recovery behaviour.

#### Scenario: Redis chaos run
- **GIVEN** the chaos suite is executed with Redis mode enabled
- **WHEN** the worker crashes mid-task
- **THEN** the system MUST rerun the task successfully using the Redis broker backend

### Requirement: Continuous Quality Gates
Stem CI MUST enforce the documented quality gates (format, analyze, test, coverage, chaos).

#### Scenario: Quality checks workflow
- **GIVEN** a pull request pipeline runs
- **WHEN** the quality workflow executes
- **THEN** it MUST run format/analyze/tests/coverage and Redis chaos suite, failing if any step fails
