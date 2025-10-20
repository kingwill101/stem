## MODIFIED Requirements

### Requirement: Retry & Dead Letter Handling
The system MUST expose tooling to inspect and replay dead letter entries while maintaining envelope metadata integrity.
#### Scenario: Operator replays DLQ entry via CLI
- **GIVEN** an operator runs `stem dlq replay default --limit 10`
- **WHEN** the CLI confirms the batch and executes the replay
- **THEN** the system MUST republish up to ten envelopes to their original queues with attempt incremented and failure metadata preserved in the result backend
- **AND** the dead letter queue MUST remove the replayed entries while recording the replay timestamp in their status meta

### Requirement: Observability & Control
Stem MUST provide command-line tooling that surfaces queue state safely for operators.
#### Scenario: Operator lists DLQ entries safely
- **GIVEN** an operator executes `stem dlq list default --page-size 20`
- **WHEN** the command runs
- **THEN** the CLI MUST display id, task name, queue, attempts, last failure reason, and `failedAt`
- **AND** it MUST provide pagination tokens and refuse to execute without the queue argument in non-interactive mode
