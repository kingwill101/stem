## 1. Research & Planning
- [ ] 1.1 Survey current CLI capabilities (`stem worker`, `stem scheduler`) to determine hooks for detach/multi.
- [ ] 1.2 Gather systemd/init best practices (security, log rotation) and record decisions in design.md.

## 2. Service Templates
- [ ] 2.1 Create systemd unit templates for worker, scheduler, and beat-like components with environment file support.
- [ ] 2.2 Provide SysV/rc.d init scripts and example `/etc/default/stem` configuration mirroring Celery’s options.
- [ ] 2.3 Add installation guide and packaging steps to copy templates into distribution artifacts.

## 3. CLI Enhancements
- [ ] 3.1 Implement `stem worker multi` command supporting start, stop, restart, status, pid/log templating, and detach.
- [ ] 3.2 Add flags for PID/log file paths with `%n`/`%h` variables and ensure directories auto-create with proper ownership.
- [ ] 3.3 Support environment file loading and validation for daemonized processes.

## 4. Observability & Health
- [ ] 4.1 Provide healthcheck command/endpoint for readiness/liveness integration.
- [ ] 4.2 Document troubleshooting (permissions, missing dirs, stale PIDs) and integrate with CLI `stem worker diagnose`.

## 5. Documentation & Validation
- [ ] 5.1 Write daemonization guide covering systemd, init scripts, unprivileged users, and log rotation.
- [ ] 5.2 `dart format`, `dart analyze`, `dart test`, plus functional tests for `stem worker multi`.
- [ ] 5.3 `openspec validate add-daemonization --strict` before review.
