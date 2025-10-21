## Overview
To align with Celery’s daemonization guide, Stem must provide first-class tooling for running workers/schedulers as managed services. Core elements:

1. **Service templates** for systemd and SysV/init, with environment variable support, logging, and security hardening.
2. **CLI helpers** (similar to `celery multi`) to manage multiple worker instances, background execution, PID/log files, and status reporting.
3. **Operational guidance** including user creation, log rotation, troubleshooting, and health checks.

## Service Templates
- **Systemd Units**: Provide `stem-worker@.service`, `stem-scheduler.service`, leveraging `EnvironmentFile=/etc/stem/stem.env`, `WorkingDirectory`, `ExecStart=stem worker start ...`, `Restart=on-failure`, `NoNewPrivileges=true`, `PrivateTmp=true`, `LimitNOFILE`, `KillMode=process`. Supports templated instances (`stem-worker@default.service`).
- **SysV/init Scripts**: Based on Celery’s `celeryd`/`celerybeat` scripts. Support environment file `/etc/default/stem`, options like `STEMD_NODES`, `STEMD_OPTS`, `STEMD_PID_FILE`, `STEMD_LOG_FILE`, `STEMD_USER`, `STEMD_GROUP`.
- Provide example configuration for both Linux distributions and mention alternatives (supervisord, system supervisor).

## CLI Enhancements
- **`stem worker multi`**:
  - Syntax: `stem worker multi <start|stop|restart|status> name1 name2 --app path --concurrency 4 --pidfile=/var/run/stem/%n.pid --logfile=/var/log/stem/%n%I.log`.
  - Expands `%n`, `%h`, `%d` for node name, hostname, date/time.
  - `--detach` runs in background (fork) writing to PID/log files.
  - `status` checks running processes by pid files.
- **Environment Loading**: `--env-file` option to load key=value pairs before exec (mirrors Celery’s `-A` and env usage). Provide validation to ensure file exists and parse errors raise helpful messages.
- **Directory Management**: Auto-create PID/log directories with proper ownership and permissions when run as unprivileged user.

## Observability & Health
- Add `stem worker healthcheck` command returning structured status (pid, uptime, queues). Useful for systemd `ExecStartPost` or Kubernetes probes.
- Provide `stem worker diagnose` to troubleshoot common daemon issues (missing pidfile, log path, permission errors), referencing docs.

## Security & Hardening
- Document recommended systemd hardening flags (e.g., `ProtectSystem=full`, `ProtectHome=read-only`, `CapabilityBoundingSet=`) and include defaults in template.
- Encourage unprivileged user `stem` with limited permissions, and log/pid directories owned by that user.

## Documentation
- Daemonization guide should include:
  - Systemd unit usage (enable/start, environment files, overrides).
  - SysV init script instructions.
  - Running under supervisors (supervisord, circus, docker).
  - Managing multiple nodes with CLI multi command.
  - Troubleshooting (stale pid, permission issues).

## Compatibility
- Existing CLI remains unchanged unless new `multi`/`--detach` flags are used.
- Service templates optional; no breaking changes for users who continue using custom setups.
