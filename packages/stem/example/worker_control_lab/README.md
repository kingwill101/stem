# Worker Control Lab

This lab demonstrates Stem's worker control commands (`ping`, `stats`,
`inspect`, `revoke`, and `shutdown`) with two worker processes sharing a
Redis broker/result backend. It is designed to make it easy to practice
operational workflows against live workers.

## Topology

- **Redis** – broker, result backend, and revoke store.
- **Workers** – two worker processes (`control-alpha`, `control-bravo`) listening
  on the `control` queue.
- **Producer** – enqueues long-running tasks so you can inspect and revoke them.

## Quick Start (Docker Compose)

```bash
cd example/worker_control_lab
# or from repo root:
# cd packages/stem/example/worker_control_lab

docker compose up --build
```

The producer prints task IDs to the console. Copy one of the long task IDs for
use in the revoke command below.

In a separate terminal on the host, run the control commands:

```bash
export STEM_BROKER_URL=redis://localhost:6379/0
export STEM_RESULT_BACKEND_URL=redis://localhost:6379/1
export STEM_REVOKE_STORE_URL=redis://localhost:6379/2

# Ping both workers

just build-cli
just stem worker ping \
  --worker control-alpha --worker control-bravo

# Inspect worker stats

just stem worker stats --worker control-alpha

# Inspect active tasks and revocations

just stem worker inspect --worker control-alpha

# Revoke a long-running task (terminate it if already running)

just stem worker revoke \
  --task <TASK_ID> \
  --terminate \
  --reason "demo revoke"

# Request a warm shutdown for one worker

just stem worker shutdown \
  --worker control-bravo \
  --mode warm
```

Stop the stack with:

```bash
docker compose down
```

## Local build + Docker deps (just)

```bash
just deps-up
just build
just build-cli
# In separate terminals:
WORKER_NAME=control-alpha just run-worker
WORKER_NAME=control-bravo just run-worker
just run-producer
# Or:
just tmux
```

When running locally, export the same `STEM_*` variables before using the CLI:

```bash
export STEM_BROKER_URL=redis://localhost:6379/0
export STEM_RESULT_BACKEND_URL=redis://localhost:6379/1
export STEM_REVOKE_STORE_URL=redis://localhost:6379/2
```

## What to Observe

- `stem worker ping` should return a reply from both workers.
- `stem worker stats` reports queue depth, inflight work, and subscriptions.
- `stem worker inspect` shows currently running tasks and any revocation entries.
- `stem worker revoke --terminate` cancels a long-running task (watch the worker
  logs for a revoke event).
- `stem worker shutdown` transitions the targeted worker through a warm
  shutdown; the other worker continues processing.

## Notes

- The producer writes task IDs to STDOUT. You can also set `TASK_ID_FILE` to
  write IDs to a file (for example: `TASK_ID_FILE=./task-ids.txt`).
- `LONG_TASK_STEPS` controls how long each long task runs (default: 12 seconds).
