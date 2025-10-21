# Daemonization Guide

Stem ships systemd units, SysV init scripts, and CLI helpers so you can manage
workers and schedulers the same way Celery deployments use `celery multi`.
This guide walks through a concrete example using the assets under
`templates/`.

## Prerequisites

- Create an unprivileged `stem` user and group.
- Ensure the Stem CLI binary (`stem`) and worker launcher script/binary (for
  example, `/usr/local/bin/stem-worker`) are installed and executable by the
  `stem` user.
- Copy the service templates from `templates/` into your packaging workflow:
  - `templates/systemd/stem-worker@.service`
  - `templates/systemd/stem-scheduler.service`
  - `templates/sysv/init.d/stem-worker`
  - `templates/sysv/init.d/stem-scheduler`
  - `templates/etc/default/stem`

## Example: systemd-managed worker

1. Install the unit files:

   ```bash
   sudo install -D templates/systemd/stem-worker@.service \
     /etc/systemd/system/stem-worker@.service
   sudo install -D templates/etc/default/stem /etc/stem/stem.env
   sudo install -d -o stem -g stem /var/lib/stem /var/log/stem /var/run/stem
   ```

2. Point `STEM_WORKER_COMMAND` at the worker executable and add any CLI flags:

   ```bash
   sudo tee -a /etc/stem/stem.env > /dev/null <<'EOF'
   STEM_WORKER_COMMAND="/usr/local/bin/stem-worker --queues=default,critical"
   EOF
   ```

3. Enable and start an instance named `alpha`:

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now stem-worker@alpha.service
   sudo systemctl status stem-worker@alpha.service
   ```

   systemd expands the unit’s templates so the worker logs to
   `/var/log/stem/alpha.log` and maintains `/run/stem/alpha.pid`. The service
   restarts on failure and applies the hardening flags defined in the unit.
   Install a matching `logrotate` snippet (for example, `/etc/logrotate.d/stem`)
   to rotate `/var/log/stem/*.log` when journald is not used.

4. Manage additional nodes with the Stem CLI:

   ```bash
   sudo STEM_WORKER_COMMAND="/usr/local/bin/stem-worker" \
     stem worker multi status alpha --pidfile=/run/stem/%n.pid
   sudo STEM_WORKER_COMMAND="/usr/local/bin/stem-worker" \
     stem worker multi restart alpha --pidfile=/run/stem/%n.pid \
     --logfile=/var/log/stem/%n.log --env-file=/etc/stem/stem.env
   ```

## Example: SysV init script

For distributions still using SysV init, install the scripts and defaults file:

```bash
sudo install -D templates/sysv/init.d/stem-worker /etc/init.d/stem-worker
sudo install -D templates/etc/default/stem /etc/default/stem
sudo chmod 755 /etc/init.d/stem-worker
sudo update-rc.d stem-worker defaults
```

Adjust `/etc/default/stem` to define the nodes and launcher command:

```bash
STEMD_NODES="alpha beta"
STEMD_COMMAND="/usr/local/bin/stem-worker --queues=background"
```

Start and stop workers:

```bash
sudo service stem-worker start
sudo service stem-worker status
sudo service stem-worker stop
```

The script wraps `stem worker multi` so PID/log directories are created
automatically and environment files are loaded before the worker process
starts.

## Scheduler (Beat) Service

The templates include `stem-scheduler.service` and a matching SysV script. Set
`STEM_SCHEDULER_COMMAND` (for example, `/usr/local/bin/stem-scheduler`) in
`/etc/stem/stem.env` or `/etc/default/stem`, then enable the service:

```bash
sudo systemctl enable --now stem-scheduler.service
```

## Docker Example

If you prefer containerized workers, the repository ships
`examples/daemonized_worker/` with a `Dockerfile` and entrypoint script that rely
on `stem worker multi` directly (no systemd required). Build it from the repo
root:

```bash
docker build -f examples/daemonized_worker/Dockerfile -t stem-multi .
docker run --rm -e STEM_WORKER_COMMAND="dart run examples/daemonized_worker/bin/worker.dart" stem-multi
```

Tune `STEM_WORKER_COMMAND`, `STEM_WORKER_NODES`, and the PID/log templates via
environment variables to mirror your production configuration.

## Troubleshooting

- **Permission denied writing PID/log** – ensure `/var/run/stem` and
  `/var/log/stem` are owned by the `stem` user.
- **Stale PID file** – `stem worker multi status` removes stale entries; use it
  before starting new nodes.
- **Customising systemd settings** – use `systemctl edit stem-worker@.service`
  to create drop-in overrides without modifying the shipped template.
- **Health probes** – `stem worker healthcheck --pidfile=/var/run/stem/<node>.pid`
  returns exit code `0` when the process is alive. Run `stem worker diagnose`
  with the PID/log paths to identify missing directories or stale PID files.
