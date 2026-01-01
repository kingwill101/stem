## Context
We are standardizing database drivers on ormed, starting with SQLite. The CLI will also move from args to artisanal, which provides a compatible args API plus richer TUI helpers.

## Goals / Non-Goals
- Goals:
  - Move SQLite driver migrations and schema management to ormed.
  - Keep runtime behavior and public APIs stable while improving CLI UX.
- Non-Goals:
  - Reworking task/workflow semantics or CLI command surface area.
  - Refactoring other drivers in this change.

## Decisions
- Decision: Use `ormed_cli:ormed init` inside the SQLite driver package to generate and manage migration assets.
  - Rationale: Aligns with ormed guidance and keeps migrations standardized.
- Decision: Use `package:artisanal/args.dart` as a drop-in replacement for args in the CLI.
  - Rationale: Preserve parser API while enabling TUI helpers for output.

## Risks / Trade-offs
- Risk: Migration bootstrap changes could alter initialization order.
  - Mitigation: Keep table names, indices, and migration history compatible and add regression tests.
- Risk: CLI output changes may affect scripts that parse output.
  - Mitigation: Keep existing command behavior and only enhance formatting where safe; document any visible changes.

## Migration Plan
1. Run ormed init in SQLite driver package and wire generated assets.
2. Translate existing SQLite schema/migrations into ormed migrations.
3. Update tests to run against ormed migrations.
4. Replace args imports with artisanal args and update CLI output helpers.

## Open Questions
- Should we preserve existing migration filenames/ids or create a fresh baseline migration?
- Which CLI outputs are safe to enhance without breaking consumers?
