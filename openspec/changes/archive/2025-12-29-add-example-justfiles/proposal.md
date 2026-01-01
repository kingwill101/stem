## Why
Running examples from inside Docker containers depends on local workspace layout and bind mounts, which makes iteration brittle. We want a reliable, local build/run workflow while still using Docker Compose for external services.

## What Changes
- Add per-example Justfiles for examples that require external services (Postgres, Redis, OTEL, etc.).
- Build Dart binaries locally (using `dart build` to support native hooks) and run them outside containers, while Docker Compose manages dependencies.
- Provide an optional tmux workflow to launch Docker services and example processes together.
- Update example READMEs to document the new workflow.

## Impact
- Affected examples: `packages/stem/example/*` that rely on external services.
- Affected docs: example READMEs describing run instructions.
- Developer tooling: introduces `just` and optional `tmux` usage for examples.
