## ADDED Requirements
### Requirement: Local example runner via Justfiles
The system SHALL provide a `justfile` in each example directory that depends on external services, enabling local build and run while using Docker Compose for dependencies.

#### Scenario: Build and run with local binaries
- **WHEN** a developer runs `just deps-up` and `just build` in an example directory
- **THEN** required Docker services are started and the example binary is built locally into `build/` using `dart build` so native hooks run.

#### Scenario: Run uses ormed.yaml
- **WHEN** a developer runs `just run` in an example directory
- **THEN** the example uses the `ormed.yaml` file in that directory to configure database drivers unless overridden.

### Requirement: Tmux launch option
The system SHALL provide a Justfile target to launch Docker dependencies and example processes inside a tmux session.

#### Scenario: Start tmux session
- **WHEN** a developer runs `just tmux`
- **THEN** a tmux session with dedicated windows/panes for each process is created or attached and processes start.

### Requirement: Example documentation for local workflow
The system SHALL document the local build + Docker dependencies workflow in each affected example README.

#### Scenario: README guidance
- **WHEN** a developer opens an example README
- **THEN** it documents the `just` targets for dependencies, build, run, and tmux usage.
