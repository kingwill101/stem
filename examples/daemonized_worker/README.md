# Dockerized Multi-Worker Example

This example shows how to launch Stem workers inside a Docker container using
`stem worker multi`. The entrypoint invokes the repository's CLI via
`dart run bin/stem.dart` and manages worker processes with PID/log templates.

## Build the Image

From the repository root:

```bash
docker build -f examples/daemonized_worker/Dockerfile -t stem-multi .
```

## Run a Worker

By default the entrypoint starts a single stub worker and keeps the container
alive. Override `STEM_WORKER_COMMAND` to point at your real worker launcher.

```bash
docker run --rm \
  -e STEM_WORKER_COMMAND="dart run examples/daemonized_worker/bin/worker.dart" \
  -e STEM_WORKER_NODES="alpha beta" \
  stem-multi
```

Environment variables understood by the entrypoint:

| Variable | Default | Purpose |
| -------- | ------- | ------- |
| `STEM_WORKER_COMMAND` | `dart run examples/daemonized_worker/bin/worker.dart` | Command executed for each node (passed via `--command-line`). |
| `STEM_WORKER_NODES` | `alpha` | Space-separated node names. |
| `STEM_WORKER_PIDFILE_TEMPLATE` | `/var/run/stem/%n.pid` | PID file template (supports `%n`, `%h`, `%I`, `%d`). |
| `STEM_WORKER_LOGFILE_TEMPLATE` | `/var/log/stem/%n.log` | Log file template used by `stem worker multi start`. |
| `STEM_WORKER_WORKDIR` | `/app` | Working directory for launched processes. |
| `STEM_WORKER_MULTI_OPTS` | *(empty)* | Extra arguments forwarded to `stem worker multi start`. |

To stop all workers, send `CTRL+C` or `docker stop`. The trap handler invokes
`stem worker multi stop` with the same PID template to terminate running nodes.

## Notes

- The container does not run `systemd`; it uses the CLI directly. For
  host-level daemonization (systemd/SysV), use the templates under `templates/`
  instead.
- The stub worker simply logs heartbeats and responds to termination signals.
  Replace `STEM_WORKER_COMMAND` with your actual Dart worker entrypoint.
- When running against real brokers/backends, remember to set `STEM_BROKER_URL`,
  `STEM_RESULT_BACKEND_URL`, etc., in the container environment.
