## ADDED Requirements

### Requirement: Comprehensive Feature Examples
Stem MUST ship runnable examples that demonstrate every major capability (core pipeline, worker operations/control, observability, security, deployment, and quality gates) so users can learn by executing real code.

#### Scenario: Delayed and rate-limited enqueue demo
- **GIVEN** a developer runs the delayed-rate-limited example
- **WHEN** they enqueue tasks with ETA and rate limits
- **THEN** the example MUST show tokens being denied/granted, priorities clamped, and delayed deliveries observable via logs or CLI

#### Scenario: DLQ operations sandbox
- **GIVEN** the DLQ example is executed
- **WHEN** tasks exhaust retries
- **THEN** the demo MUST populate the dead-letter queue and provide scripts/commands to list and replay entries successfully

#### Scenario: Worker control lab
- **GIVEN** the worker control example is running
- **WHEN** operators issue `stem worker ping|stats|revoke|shutdown`
- **THEN** responses MUST be shown in the console and revocations MUST prevent re-delivery without manual replay

#### Scenario: Autoscaling walkthrough
- **GIVEN** the autoscaling example is running
- **WHEN** workload increases and then subsides
- **THEN** the example MUST expand and contract worker concurrency within configured min/max limits, logging the transitions

#### Scenario: Scheduler observability drill
- **GIVEN** the scheduler observability example is running
- **WHEN** schedules fire with intentional drift/failures
- **THEN** the example MUST emit schedule-entry signals, log drift metrics, and include CLI commands to inspect schedule history

#### Scenario: Signing key rotation exercise
- **GIVEN** the signing rotation example is executed
- **WHEN** the active key changes
- **THEN** new tasks MUST be accepted with the new key while workers still validate the old key during the overlap window

#### Scenario: Ops health suite
- **GIVEN** the ops health example is active
- **WHEN** `stem worker status --stream`, `stem observe tasks`, and healthcheck commands are run
- **THEN** the example MUST output live heartbeat data, queue states, and readiness information

#### Scenario: Quality gates runner
- **GIVEN** the quality gate example scripts are launched
- **WHEN** the pipeline runs
- **THEN** format/analyze/test/coverage/chaos steps MUST execute and report pass/fail outcomes for each gate

#### Scenario: Progress and heartbeat reporting
- **GIVEN** the progress example is running
- **WHEN** a long-running task sends heartbeat/progress updates
- **THEN** observers MUST see progress reflected in logs/result backend meta and via CLI inspection
