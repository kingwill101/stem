## ADDED Requirements

### Requirement: Workflow store bootstrap snippets
Stem MUST expose the SQL/Lua/schema snippets required to provision workflow stores via CLI so operators can audit and apply them outside the application runtime.

#### Scenario: Operator prints Postgres schema
- **GIVEN** an operator runs `stem wf bootstrap postgres`
- **WHEN** the command executes successfully
- **THEN** it MUST output the SQL statements needed to create workflow tables, matching the adapter implementation.

#### Scenario: Operator prints Redis scripts
- **GIVEN** an operator runs `stem wf bootstrap redis`
- **WHEN** the command executes
- **THEN** it MUST output the Lua scripts or key definitions used for atomic workflow operations.
