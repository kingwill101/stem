## ADDED Requirements

### Requirement: Workflow agent helper command
Stem CLI MUST provide a command that emits workflow-specific guidance suitable for inclusion in AGENTS/CLAUDE documentation so automated assistants understand supported operations and safety caveats.

#### Scenario: Agent help includes workflow commands and safety tips
- **GIVEN** an operator runs `stem wf agent-help`
- **WHEN** the command executes successfully
- **THEN** it MUST print Markdown containing:
  - A summary of workflow concepts (durable steps, idempotency helper)
  - A list of CLI commands (`start`, `show`, `waiters`, `emit`, `cancel`)
  - Safety notes (verify policies before cancelling, use idempotency helper)
