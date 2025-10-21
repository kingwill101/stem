## Why
- Celery provides curated daemonization tooling (systemd/init scripts, `celery multi`, PID/log management, unprivileged users). Stem lacks first-class support, forcing operators to handcraft service files and manage lifecycles manually.
- Stem CLI doesn’t offer multi-instance helpers, PID/log rotation defaults, or guidance for running under systemd/supervisors.
- Without a supported daemonization story, production adoption is hindered and misconfiguration risk increases.

## What Changes
- Deliver official systemd units and init-script templates for Stem worker, scheduler, and CLI processes, including environment file support and security hardening.
- Extend Stem CLI with multi-instance management (`stem worker multi start|restart|stop`), PID/log path templating, and detach/background execution.
- Provide documentation and tooling to create unprivileged service accounts, manage log rotation, handle status checks, and integrate health probes.
- Add daemonization-oriented configuration validation (PID dir permissions, environment loading) and troubleshooting guidance.

## Impact
- Adds new scripts/templates to the repo; packaging/distribution steps must include them.
- CLI gains new commands/flags; existing behaviour remains unchanged unless features are used.
- Operators benefit from opinionated defaults while retaining flexibility to customize.
