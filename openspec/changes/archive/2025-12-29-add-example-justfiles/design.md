## Context
Examples currently run inside Docker containers with bind mounts to local checkouts. This breaks when local workspace paths differ. We need a local build/run path that still leverages Docker for external services.

## Goals / Non-Goals
- Goals:
  - Provide a consistent local workflow for examples that require external services.
  - Keep Docker Compose for dependencies (Postgres, Redis, OTEL).
  - Offer an optional tmux launcher for multi-process examples.
- Non-Goals:
  - Replacing Docker Compose with alternative dependency managers.
  - Forcing all examples to adopt Justfiles (only those with external deps).

## Decisions
- Use per-example `justfile` targets to standardize build/run steps.
- Compile Dart binaries locally (outside containers) into `build/` under each example using `dart build` to ensure native hooks run.
- Keep tmux optional: include a `tmux` target that creates/attaches to a session, but do not require tmux for standard usage.

## Risks / Trade-offs
- Adds new tooling expectations (`just`, optional `tmux`). Mitigate via README notes and graceful fallbacks.
- Example-specific tmux layouts may diverge; mitigate with naming conventions and shared target structure.

## Migration Plan
- Add Justfiles and README updates per example.
- Keep existing Docker workflows intact so current users are not blocked.

## Open Questions
- Should we standardize the output binary naming across examples (e.g., `build/<example>`)?
- Should the tmux session name be derived from the example directory or be configurable?
