---
title: Daemonization Guide
sidebar_label: Daemonization
sidebar_position: 2
slug: /workers/daemonization
---

Stem now ships opinionated service templates and CLI helpers so you can manage
workers like you would with Celery’s `celery multi`. This guide mirrors
`docs/process/daemonization.md` and walks through real examples.

## Prerequisites

- Create an unprivileged `stem` user/group.
- Install the Stem CLI and your worker launcher binary/script (for example,
  `/usr/local/bin/stem-worker`).
- Copy templates from the repository (`templates/`) into your packaging step:
  systemd units, SysV scripts, and `/etc/default/stem`.

## Worker entrypoint

The daemonization templates expect a worker launcher that runs until signaled.
This is the stub worker used by the daemonized worker example:

```dart title="worker.dart" file=<rootDir>/../packages/stem/example/daemonized_worker/bin/worker.dart#daemonized-worker-main

```

## Systemd Example

```bash
sudo install -D templates/systemd/stem-worker@.service \
  /etc/systemd/system/stem-worker@.service
sudo install -D templates/etc/default/stem /etc/stem/stem.env
sudo install -d -o stem -g stem /var/lib/stem /var/log/stem /var/run/stem
```

Set the worker command and queues inside `/etc/stem/stem.env`:

```bash
STEM_WORKER_COMMAND="/usr/local/bin/stem-worker --queues=default,critical"
```

Enable an instance named `alpha`:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now stem-worker@alpha.service
sudo journalctl -u stem-worker@alpha.service
```

The unit expands PID/log templates, reloads via `stem worker multi restart`, and
applies the hardening flags (`NoNewPrivileges`, `ProtectSystem`, etc.). Install a matching
logrotate snippet (for example, `/etc/logrotate.d/stem`) when journald is not used so
`/var/log/stem/*.log` is rotated regularly.

## SysV Example

```bash
sudo install -D templates/sysv/init.d/stem-worker /etc/init.d/stem-worker
sudo install -D templates/etc/default/stem /etc/default/stem
sudo chmod 755 /etc/init.d/stem-worker
sudo update-rc.d stem-worker defaults
```

`/etc/default/stem` controls the nodes and command:

```bash
STEMD_NODES="alpha beta"
STEMD_COMMAND="/usr/local/bin/stem-worker --queues=background"
```

Run it like any other service:

```bash
sudo service stem-worker start
sudo service stem-worker status
sudo service stem-worker stop
```

## Scheduler

Set `STEM_SCHEDULER_COMMAND` in the environment file and enable
`stem-scheduler.service` (systemd) or `/etc/init.d/stem-scheduler` (SysV).

## Docker Example

`examples/daemonized_worker/` contains a Dockerfile and entrypoint that run
`stem worker multi` directly. Build and run from the repo root:

```
docker build -f examples/daemonized_worker/Dockerfile -t stem-multi .
docker run --rm -e STEM_WORKER_COMMAND="dart run examples/daemonized_worker/bin/worker.dart" stem-multi
```

Override `STEM_WORKER_*` environment variables to control nodes, PID/log
templates, and the worker command.

## Troubleshooting

- Missing directories → ensure `/var/log/stem` and `/var/run/stem` exist with
  `stem:stem` ownership.
- Stale PID files → `stem worker multi status` cleans them up.
- Custom systemd options → use `systemctl edit stem-worker@.service` to create a
  drop-in override.
- Health probes → `stem worker healthcheck --pidfile=/var/run/stem/<node>.pid` returns exit
  code `0` when the process is alive. Run `stem worker diagnose` with the PID/log paths to
  identify missing directories or stale PID files.
