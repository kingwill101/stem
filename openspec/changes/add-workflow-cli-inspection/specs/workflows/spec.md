## ADDED Requirements

### Requirement: Workflow CLI inspection commands
The Stem CLI MUST expose commands to inspect workflow waiters, leases, and cancellation metadata so operators can debug long-running runs without database access.

#### Scenario: List runs waiting on a topic
- **GIVEN** one or more runs are suspended on `payment.received`
- **WHEN** an operator runs `stem wf waiters --topic payment.received`
- **THEN** the CLI MUST display the run identifiers, suspension metadata (deadline, payload captured), and policy info.

#### Scenario: Show lease and policy details for a run
- **GIVEN** a run has an active lease and cancellation policy configured
- **WHEN** an operator runs `stem wf show <runId>`
- **THEN** the CLI MUST include lease expiry, last heartbeat time, and cancellation policy fields in the output.
