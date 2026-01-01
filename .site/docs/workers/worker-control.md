---
title: Worker Control
sidebar_label: Worker Control CLI
sidebar_position: 1
slug: /workers/control
---

Stem exposes a broker-backed control plane so operators can inspect, revoke, and
coordinate workers without restarts. This guide walks through the CLI surface,
revocation durability, and termination semantics for inline vs isolate handlers.

## Remote control primer

- **Inspect** commands read worker state (`stem worker stats`, `stem worker inspect`).
- **Control** commands mutate state (`stem worker revoke`, `stem worker shutdown`).
- Commands broadcast to all workers unless you pass `--worker` to target
  specific IDs.
- Use `--namespace` to match the control namespace used by your workers.

## CLI Overview

| Command | Purpose |
| ------- | ------- |
| `stem worker ping` | Broadcast a ping and aggregate worker responses. |
| `stem worker inspect` | List in-flight tasks (and optional revoke cache) per worker. |
| `stem worker stats` | Summarize inflight counts, queue depth, and metadata. |
| `stem worker revoke` | Persist revocations and broadcast terminate/best-effort revokes. |
| `stem worker shutdown` | Request warm/soft/hard shutdown via the control channel. |
| `stem worker status` | Stream heartbeats or snapshot the backend (existing command). |
| `stem worker healthcheck` | Probe worker processes for readiness/liveness. |
| `stem worker diagnose` | Run local diagnostics for pid/log/env configuration issues. |
| `stem worker multi` | Manage multiple worker processes (start/stop/restart/status). |

Use `--namespace` to target non-default control namespaces. Omitting `--worker`
broadcasts to every worker. All commands honour the same environment variables as
`stem health` (`STEM_BROKER_URL`, `STEM_RESULT_BACKEND_URL`, TLS/signing flags).

### Quick Examples

```bash
# Ping a subset of workers by identifier
stem worker ping --worker worker-a --worker worker-b

# Inspect all workers (JSON output)
stem worker inspect --json

# Revoke a task and request termination
stem worker revoke --task 1761057... --terminate
```

For a runnable lab that exercises ping/stats/revoke/shutdown against real
workers, see `example/worker_control_lab` in the repository.

## Autoscaling Concurrency

Workers can autoscale their isolate pools between configured minimum and
maximum bounds. Enable the evaluator by passing `WorkerAutoscaleConfig` to the
worker constructor:

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/worker_control.dart#worker-control-autoscale

```

The autoscaler samples broker queue depth alongside inflight counts to decide
when to scale. Metrics expose the current setting via
`stem.worker.concurrency`, and `stem worker stats --json` includes the live
`activeConcurrency` value so dashboards can observe adjustments.

See `example/autoscaling_demo` for a queue-backlog scenario that triggers
scale-up and scale-down events.

## CLI Multi-Instance Management

`stem worker multi` orchestrates OS processes for worker nodes. It honours the
same placeholders as the service templates (`%n`, `%h`, `%I`, `%d`) when
expanding PID/log/workdir templates and uses `STEM_WORKER_COMMAND` (or
`--command`/`--command-line`) for the executable.

```bash
export STEM_WORKER_COMMAND="/usr/bin/stem-worker"
stem worker multi start alpha beta \
  --pidfile=/var/run/stem/%n.pid \
  --logfile=/var/log/stem/%n.log \
  --env-file=/etc/stem/stem.env

stem worker multi status alpha beta --pidfile=/var/run/stem/%n.pid
stem worker multi stop alpha beta --pidfile=/var/run/stem/%n.pid
```

The CLI auto-creates directories and exposes `STEM_WORKER_NODE`,
`STEM_WORKER_PIDFILE`, and `STEM_WORKER_LOGFILE` to the launched process so apps
can discover their runtime context.

## Worker Healthcheck

Use `stem worker healthcheck` inside systemd `ExecStartPost=`, Kubernetes probes,
or shell scripts to determine whether a worker process is running:

```
stem worker healthcheck \
  --node alpha \
  --pidfile=/var/run/stem/alpha.pid \
  --logfile=/var/log/stem/alpha.log \
  --json
```

Exit code `0` indicates the PID file exists and the process is alive. The JSON
payload includes the pid, timestamp captured from the PID file, and the uptime
in seconds.

## Worker Diagnostics

`stem worker diagnose` performs common checks (PID/log directories, stale PID
files, environment file parsing) to help troubleshoot daemonization issues:

```
stem worker diagnose \
  --pidfile=/var/run/stem/alpha.pid \
  --logfile=/var/log/stem/alpha.log \
  --env-file=/etc/stem/stem.env
```

Warnings and errors are printed for missing directories, unparseable PIDs, and
other configuration gaps. Use `--json` when integrating with tooling.

## Persistent Revokes

Revocations are durable so new workers or restarts continue honouring them. The
CLI resolves the backing store in this order:

1. `STEM_REVOKE_STORE_URL`
2. `STEM_RESULT_BACKEND_URL`
3. `STEM_BROKER_URL`

Supported schemes: Redis (`redis://`, `rediss://`), Postgres (`postgres://`,
`postgresql://`), a newline-delimited file (`file:///path/to/revokes.stem` or
bare path), and in-memory (`memory://` – useful for tests). Workers hydrate the
revocation cache at startup, prune expired records, and apply new control
messages. The CLI writes through the store *before* broadcasting control
messages to guarantee durability precedes visibility.

## Termination Semantics

### Inline vs isolate handlers

Stem executes tasks either inline (worker main isolate) or in dedicated child
isolates when a handler exposes an `isolateEntrypoint`. Inline handlers share the
worker event loop and can be interrupted immediately at the next checkpoint.
Isolate handlers communicate with the worker only when they emit control signals
(heartbeat, lease extension, progress). That difference governs how quickly a
`--terminate` revoke takes effect.

### Inline handler example

```dart title="tasks/inline_report_task.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/worker_control.dart#worker-control-inline

```

### Isolate handler example

```dart title="tasks/image_render_task.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/worker_control.dart#worker-control-isolate

```

`stem worker revoke --terminate` throws `TaskRevokedException` the next time an
inline handler calls `TaskContext.heartbeat`, `extendLease`, or `progress`,
allowing the worker to cancel and record the task as cancelled. Isolate handlers
must emit cooperative checkpoints (heartbeat/lease/progress) to be interrupted;
otherwise they finish naturally.

### Cooperative checkpoints for isolate handlers

Make sure isolate entrypoints call one of the cooperative helpers inside any
long-running loop. Each helper throws `TaskRevokedException` when a terminate
revoke is pending, which lets the handler fail fast.

```dart title="tasks/crunch.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/worker_control.dart#worker-control-crunch

```

For CPU-bound workloads, batch work or insert `await Future<void>.delayed(...)`
so the isolate yields periodically. Without checkpoints the worker cannot
pre-empt the task until it returns on its own.

Operators should pair `--terminate` with `stem worker inspect` to monitor
inflight tasks that still need to quiesce. If a handler never emits heartbeats,
add them or implement explicit cancellation logic.

## Shutdown Modes and Lifecycle Guards

Use `stem worker shutdown --mode warm|soft|hard` to trigger runtime shutdowns:

- **Warm** stops fetching new deliveries and drains current work.
- **Soft** issues terminate revocations, then escalates to hard after the
  configured grace period if tasks continue running.
- **Hard** immediately requeues active deliveries and terminates isolates.

By default, workers install signal handlers that map `SIGTERM` to warm,
`SIGINT` to soft, and `SIGQUIT` to hard. Disable them by constructing the worker
with `WorkerLifecycleConfig(installSignalHandlers: false)` when embedding Stem
inside a larger host that already owns signal routing.

Lifecycle guards can also recycle isolates automatically:

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/worker_control.dart#worker-control-lifecycle

```

Recycling occurs after the active task finishes; the worker logs the recycle
reason and spawns a fresh isolate before accepting new work.

## Configuration Summary

| Variable | Purpose |
| --- | --- |
| `STEM_REVOKE_STORE_URL` | Override the revoke store target (defaults to backend or broker). |
| `STEM_CONTROL_NAMESPACE` | Override the control namespace (defaults to heartbeat namespace). |
| `STEM_WORKER_NAMESPACE` | Logical grouping for worker IDs/queues. |
| `STEM_CONTROL_TIMEOUT` | Default control command timeout (e.g. `5s`). |

Set `STEM_REVOKE_STORE_URL` to the datastore you want to back revocations. For
example, to use Postgres alongside the result backend:

```bash
export STEM_REVOKE_STORE_URL=postgres://stem:secret@db:5432/stem
```

## Additional Resources

- `stem worker --help` – built-in CLI usage for each subcommand.
- The `examples/` directory in the Stem repository demonstrates control
  commands alongside worker lifecycle signals.
