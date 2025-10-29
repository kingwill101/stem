# Stem Service Templates

This directory provides reference templates for packaging Stem as a managed
service.

## Layout

- `systemd/` contains unit files that can be installed under
  `/lib/systemd/system/` (or `/etc/systemd/system/` for site overrides).
  - `stem-worker@.service` is an instantiated unit for worker nodes
    (`systemctl enable --now stem-worker@alpha.service`).
  - `stem-scheduler.service` runs the scheduler/beat process.
- `sysv/init.d/` contains SysV init scripts compatible with Debian/Ubuntu
  (`update-rc.d`) and RHEL/CentOS (`chkconfig`) tooling.
- `etc/default/stem` is an example environment file sourced by the SysV
  scripts and referenced by the systemd units.

## Packaging Guidance

1. Install the systemd units into your package under
   `/lib/systemd/system/` and include them in the `%post` scripts (RPM) or
   `postinst` (DEB) to run `systemctl daemon-reload`.
2. Copy the SysV scripts to `/etc/init.d/` for platforms that do not rely on
   systemd. Ensure they are marked executable (`chmod 755`) and register them
   with `update-rc.d` or `chkconfig` during install.
3. Ship `/etc/default/stem` (or `/etc/sysconfig/stem`) as a config file so
   operators can override runtime settings. Pair it with `/etc/stem/stem.env`
   for secret/environment management.
4. Populate the command variables in `/etc/default/stem` (or `/etc/sysconfig/stem`):
   set `STEMD_COMMAND` to the worker launcher binary/script and
   `STEM_SCHEDULER_COMMAND` for the scheduler process. `stem worker multi`
   reads `STEM_WORKER_COMMAND` from the environment, so ensure the exported
   value resolves to the actual worker executable within your package.
5. Create the runtime directories `/var/run/stem`, `/var/log/stem`, and
   `/var/lib/stem` owned by the unprivileged `stem` user inside your package
   scripts to satisfy the templates’ expectations.
6. Document the installation steps in release notes and reference
   `doc/process/daemonization.md` (added in this change) so operators know how
   to enable the services.

These templates are intentionally conservative—encourage operators to use
`systemctl edit` or override files for per-environment customization while
keeping the shipped defaults minimal and secure.
