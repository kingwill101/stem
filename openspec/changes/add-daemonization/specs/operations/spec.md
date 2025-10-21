## ADDED Requirements
### Requirement: Official Service Templates
Stem MUST distribute supported systemd unit and SysV/init templates for running workers and schedulers as managed services.

#### Scenario: Operator installs systemd unit
- **GIVEN** the packaged `stem-worker@.service`
- **WHEN** an operator enables and starts `stem-worker@default.service`
- **THEN** the service MUST launch a Stem worker with configured options, write PID/log files, and restart on failure per template defaults.

### Requirement: CLI Multi-Instance Management
Stem CLI MUST provide commands to start, stop, restart, and check status of multiple worker instances with PID/log templating.

#### Scenario: Start multiple workers via CLI
- **GIVEN** the command `stem worker multi start w1 w2 --pidfile=/var/run/stem/%n.pid --logfile=/var/log/stem/%n.log`
- **WHEN** executed
- **THEN** the CLI MUST launch two background workers named `w1` and `w2`, create PID/log files with substituted names, and report success or failures per node.

#### Scenario: Stop workers via PID files
- **GIVEN** workers started with PID files
- **WHEN** `stem worker multi stop w1 w2` is executed
- **THEN** the CLI MUST read the PID files, send warm shutdown signals, wait for exit, and remove PID files.

### Requirement: Environment & Directory Validation
Daemonization tooling MUST support environment files, auto-create PID/log directories with proper ownership, and validate configurations.

#### Scenario: Environment file loading
- **GIVEN** `--env-file=/etc/stem/stem.env`
- **WHEN** the worker is started via systemd or CLI
- **THEN** the process MUST load environment variables from the file before initializing the Stem app, failing with descriptive error if parsing fails.

#### Scenario: Directory auto-creation
- **GIVEN** PID/log paths under `/var/run/stem` and `/var/log/stem`
- **WHEN** the worker starts as user `stem`
- **THEN** the tooling MUST ensure directories exist with user ownership, creating them if missing.
