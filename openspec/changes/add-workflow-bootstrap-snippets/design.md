# Design: Workflow bootstrap snippets

## Overview
Implement CLI commands or export utilities per adapter to print the schema/scripts powering workflow stores:
- `stem wf bootstrap postgres` – outputs SQL schema for workflow tables.
- `stem wf bootstrap redis` – outputs Lua scripts or key conventions.
- `stem wf bootstrap sqlite` – prints the CREATE TABLE statements.

Adapters expose helper functions returning the relevant strings so both CLI and docs can reuse them.

## Risks
Minimal; ensure exports stay in sync with actual implementation by sharing source constants.
