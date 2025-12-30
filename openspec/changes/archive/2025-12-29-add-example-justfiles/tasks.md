## 1. Discovery
- [x] 1.1 Inventory examples that depend on external services (Redis, Postgres, OTEL, etc.).
- [x] 1.2 Record each example's dependency stack and Docker Compose file path.

## 2. Justfiles
- [x] 2.1 Add a `justfile` to each identified example with `deps-up`, `deps-down`, `build`, `run`, and `clean` targets.
- [x] 2.2 Ensure `build` compiles local binaries with `dart build` (to support native hooks) into `build/`.
- [x] 2.3 Ensure `run` executes the local binary and reads `ormed.yaml` from the example directory by default.
- [x] 2.4 Allow `deps-up`/`deps-down` to use the example's Docker Compose file, with an override env var if needed.

## 3. Tmux Workflow
- [x] 3.1 Add a `tmux` (or `tmux-up`) target that launches Docker deps and example processes in a tmux session.
- [x] 3.2 Define a consistent session naming convention and window/pane layout per example.

## 4. Documentation
- [x] 4.1 Update each affected example README with the local build + Docker deps workflow.
- [x] 4.2 Document tmux as optional tooling and provide basic usage instructions.
