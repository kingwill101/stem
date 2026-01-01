# Design: Workflow agent helper output

## Overview
Implement a CLI subcommand that prints Markdown-formatted guidance covering:
- Core workflow concepts (durable steps, idempotency helper).
- Key CLI commands (`start`, `show`, `waiters`, `emit`, `cancel`).
- Safety tips (double-check policies before cancelling).

The command pulls content from templates stored in the CLI package to keep documentation centralised.

## Implementation Steps
- Add command `stem wf agent-help` that renders a Markdown template with the current command list (pull metadata from CLI command definitions where possible).
- Provide a test verifying output contains expected sections.
- Document usage in README.
