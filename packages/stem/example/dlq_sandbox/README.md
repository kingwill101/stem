# Dead-Letter Queue Sandbox

This example makes it easy to generate dead-lettered tasks, inspect them, and
replay them back into the default queue using Stem's CLI tooling. The task will
fail on its first attempts, land in the DLQ, and then succeed the moment it is
replayed.

## Topology

- **Redis** – broker and result backend for the sandbox.
- **Worker** – consumes the `default` queue and logs task lifecycle signals.
- **Producer** – enqueues a few invoices that intentionally fail until replayed.
- **CLI helper** – gives you an environment with Stem configured so you can run
  `stem dlq` commands.

## Quick Start (Docker Compose)

```bash
cd examples/dlq_sandbox
docker compose up --build worker producer
```

Wait for the worker log to show each task failing after three attempts and being
moved to the dead-letter queue. Once everything is idle, run the CLI commands in
separate terminals:

1. **List DLQ entries**

   ```bash
   docker compose run --rm cli \
     dart run bin/stem.dart dlq list --queue default --limit 10
   ```

2. **Inspect one entry** (replace `<TASK_ID>` with the id from the list output)

   ```bash
   docker compose run --rm cli \
     dart run bin/stem.dart dlq show --queue default --id <TASK_ID>
   ```

3. **Replay the failures**

   ```bash
   docker compose run --rm cli \
     dart run bin/stem.dart dlq replay --queue default --limit 10 --yes
   ```

   The worker will log that each invoice is now processed successfully because
the replay metadata adds `replayCount > 0` to the task state.

4. **Verify the queue is empty**

   ```bash
   docker compose run --rm cli \
     dart run bin/stem.dart dlq list --queue default --limit 10
   ```

   You should see `No dead letter entries found.`

When you are done, tear the stack down:

```bash
docker compose down
```

## Manual Workflow

If you prefer running everything locally without Docker:

```bash
# Start Redis
docker run --rm -p 6382:6379 redis:7-alpine

# Terminal 1: worker
cd examples/dlq_sandbox
STEM_BROKER_URL=redis://localhost:6382/0 \
STEM_RESULT_BACKEND_URL=redis://localhost:6382/1 \
dart run bin/worker.dart

# Terminal 2: producer
cd examples/dlq_sandbox
STEM_BROKER_URL=redis://localhost:6382/0 \
STEM_RESULT_BACKEND_URL=redis://localhost:6382/1 \
dart run bin/producer.dart

# Terminal 3: CLI operations
cd examples/dlq_sandbox
STEM_BROKER_URL=redis://localhost:6382/0 \
STEM_RESULT_BACKEND_URL=redis://localhost:6382/1 \
dart run ../../bin/stem.dart dlq list --queue default --limit 10
```

Repeat the CLI command with `dlq replay ... --yes` to requeue entries.

## What to Observe

- Worker logs show repeated failures until the task is replayed; the replayed
  task succeeds immediately and prints `[worker][success]`.
- Signals (`task_retry`, `task_failed`, `task_succeeded`) surface the lifecycle
  transitions.
- The CLI updates result backend metadata with `replayCount`, providing a simple
  way for the handler to detect a replay.
