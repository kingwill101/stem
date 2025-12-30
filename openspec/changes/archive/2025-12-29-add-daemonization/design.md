## Overview
To align with Celery’s daemonization guide, Stem must provide first-class tooling for running workers/schedulers as managed services. Core elements:

## Research Snapshot
- `stem worker` presently offers only control-plane subcommands (`ping`, `inspect`, `stats`, `revoke`, `shutdown`, `status`). There is no built-in runner, detach mode, or helper comparable to `celery multi`; operators invoke workers from their own Dart apps or supervision scripts.
- `stem schedule` manages definitions (`list`, `show`, `apply`, `delete`, `dry-run`) but does not provide a scheduler/beat process. Any periodic execution must be orchestrated externally.
- The CLI has no existing flags for PID/log path templating or environment-file loading, so the new daemonization commands must introduce these concepts while leaving the current UX untouched.
- Worker status/signals are only surfaced through the control channel, so multi-instance management will need to layer process supervision, PID tracking, and detach behaviour on top of the existing control APIs.

1. **Service templates** for systemd and SysV/init, with environment variable support, logging, and security hardening.
2. **CLI helpers** (similar to `celery multi`) to manage multiple worker instances, background execution, PID/log files, and status reporting.
3. **Operational guidance** including user creation, log rotation, troubleshooting, and health checks.

## Service Templates
- **Systemd Units**: Provide `stem-worker@.service`, `stem-scheduler.service`, leveraging `EnvironmentFile=/etc/stem/stem.env`, `WorkingDirectory`, `ExecStart=stem worker start ...`, `Restart=on-failure`, `NoNewPrivileges=true`, `PrivateTmp=true`, `LimitNOFILE`, `KillMode=process`. Supports templated instances (`stem-worker@default.service`).
- **SysV/init Scripts**: Based on Celery’s `celeryd`/`celerybeat` scripts. Support environment file `/etc/default/stem`, options like `STEMD_NODES`, `STEMD_OPTS`, `STEMD_PID_FILE`, `STEMD_LOG_FILE`, `STEMD_USER`, `STEMD_GROUP`.
- Provide example configuration for both Linux distributions and mention alternatives (supervisord, system supervisor).
- Systemd decisions:
  - Run as unprivileged `User=stem`/`Group=stem`, set `RuntimeDirectory=stem` and `PIDFile=/run/stem/%i.pid` so systemd manages pid/log directories.
  - Prefer journald or `StandardOutput=append:/var/log/stem/%i.log`; document a matching `/etc/logrotate.d/stem` snippet for file-based logging.
  - Enforce `Restart=on-failure`, `RestartSec=5`, `TimeoutStopSec=30`, `KillMode=process`, and bump `LimitNOFILE` to 65536.
  - Apply hardening flags (`ProtectSystem=full`, `ProtectHome=read-only`, `PrivateTmp=true`, `NoNewPrivileges=true`, `CapabilityBoundingSet=`) while keeping configuration/log paths accessible.
  - Encourage overrides via drop-ins (`systemctl edit`) and keep templates minimal, delegating customization to environment files.
- SysV scripts should rely on `start-stop-daemon`/`daemon` helpers, source `/etc/default/stem`, expose LSB headers for chkconfig/update-rc.d, and document ownership/permission expectations for `/var/log/stem` and `/var/run/stem`.

## CLI Enhancements
- **`stem worker multi`**:
  - Syntax: `stem worker multi <start|stop|restart|status> name1 name2 --app path --concurrency 4 --pidfile=/var/run/stem/%n.pid --logfile=/var/log/stem/%n%I.log`.
  - Expands `%n`, `%h`, `%d` for node name, hostname, date/time.
  - `--detach` runs in background (fork) writing to PID/log files.
  - `status` checks running processes by pid files.
  - Defaults command execution to `STEM_WORKER_COMMAND` but accepts `--command` /
    `--command-line` overrides so packaging can inject bespoke launchers.
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
