---
title: Daemonization
slug: /workers/daemonization
---

Stem ships systemd units, SysV init scripts, and CLI helpers so you can manage
workers and schedulers using a single configuration surface. The templates live
under `templates/` and are ready to drop into packaging workflows.

## Prerequisites

- Create an unprivileged `stem` user and group.
- Install the `stem` CLI and the worker launcher (for example, `stem-worker`).
- Copy the templates you need from `templates/`:
  - `templates/systemd/stem-worker@.service`
  - `templates/systemd/stem-scheduler.service`
  - `templates/sysv/init.d/stem-worker`
  - `templates/sysv/init.d/stem-scheduler`
  - `templates/etc/default/stem`

## Worker entrypoint

The daemonization templates expect a worker launcher that runs until signaled.
This example is the stub worker used by the daemonized worker scenario:

```dart file=<rootDir>/../packages/stem/example/daemonized_worker/bin/worker.dart#daemonized-worker-main
```

## systemd workflow

1. Install the unit files and environment defaults.
2. Set `STEM_WORKER_COMMAND` in `/etc/stem/stem.env` to the worker launcher.
3. Enable and start the instance:

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now stem-worker@alpha.service
   ```

4. Use `stem worker multi` for bulk node management:

   ```bash
   sudo STEM_WORKER_COMMAND="/usr/local/bin/stem-worker" \
     stem worker multi status alpha --pidfile=/run/stem/%n.pid
   ```

## SysV workflow

1. Install the init scripts and defaults file.
2. Configure `STEMD_NODES` and `STEMD_COMMAND` in `/etc/default/stem`.
3. Start and stop workers with `service`.

## Scheduler service

Set `STEM_SCHEDULER_COMMAND` in the environment defaults, then enable the
scheduler service via systemd or SysV.

## Docker example

The repository includes `examples/daemonized_worker/` with a `Dockerfile` and
entrypoint script that call `stem worker multi` directly (no systemd required).
Tune `STEM_WORKER_COMMAND`, `STEM_WORKER_NODES`, and the PID/log templates via
environment variables to mirror production behavior.

## Troubleshooting

- **Permission denied writing PID/log** – ensure PID/log directories are owned by
  the `stem` user.
- **Stale PID file** – `stem worker multi status` removes stale entries.
- **Customizing systemd settings** – use `systemctl edit stem-worker@.service` to
  create drop-in overrides.
