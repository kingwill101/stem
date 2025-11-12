# Proposal: Workflow bootstrap automation snippets

## Problem
Operators currently rely on documentation to understand what SQL/Lua scripts underpin workflow stores. There is no easy way to audit or bootstrap these snippets (e.g., creating Postgres tables or Redis scripts) outside the implementation. Absurd provides `absurdctl init` and script exports that help operators inspect durability logic.

## Goals
- Provide commands (or build tooling) that output the schema/scripts required by each workflow store (Postgres migrations, Redis Lua, SQLite schema).
- Ensure documentation references these snippets so operators can audit and reapply them if needed.

## Non-Goals
- Changing store implementations; we focus on exposing existing artefacts.
- Automating migrations (existing migration tooling remains in place).

## Measuring Success
- Operators can run `stem wf bootstrap --backend postgres` (or similar) to print the SQL schema.
- Redis adapter exposes the Lua scripts used for atomic watcher operations.
- Documentation references how to audit these snippets.
