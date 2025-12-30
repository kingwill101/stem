## ADDED Requirements
### Requirement: CLI uses artisanal args
The CLI SHALL use `package:artisanal/args.dart` as a drop-in replacement for args while preserving the existing command behaviors and flags.

#### Scenario: Command parsing
- **WHEN** a user runs an existing CLI command with its current flags
- **THEN** the command parses arguments and executes with the same behavior as before

### Requirement: CLI output uses artisanal helpers
The CLI SHALL use artisanal output helpers to render command results with improved formatting without changing the underlying data or semantics.

#### Scenario: Workflow command output
- **WHEN** a user runs a workflow-related command
- **THEN** the output is rendered via artisanal helpers and remains semantically equivalent to the prior output
