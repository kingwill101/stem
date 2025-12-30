# Postgres Broker/Backend Example

This sample shows how to run Stem with Postgres for both the broker and the
result backend. It starts a Postgres instance via Docker Compose, spins up a
worker, and enqueues a few demo tasks.

## Prerequisites

- Dart SDK 3.3 or newer
- Docker (for the sample Postgres instance)

## Option A: Docker Compose (Postgres + worker + enqueuer)

1. Copy the environment template if you want to customise values:

   ```bash
   cp .env.example .env
   ```

2. Start Postgres, the enqueuer, and the worker:

   ```bash
   docker compose up --build worker enqueuer
   ```

   The enqueuer exposes `http://localhost:8081/enqueue`. Use the same command
   to enqueue demo jobs from another terminal or via curl:

   ```bash
   curl -X POST http://localhost:8081/enqueue \
     -H 'content-type: application/json' \
     -d '{"name": "us-east"}'
   ```

3. When finished, stop the stack:

   ```bash
   docker compose down
   ```

## Option B: Manual (local Dart processes)

### 1. Start Postgres

```bash
docker compose up postgres -d
```

Postgres will listen on `127.0.0.1:5432` with database `stem_demo` and
credentials `stem/stem`.

### 2. Export Stem environment variables

```bash
export STEM_BROKER_URL=postgres://stem:stem@127.0.0.1:5432/stem_demo
export STEM_RESULT_BACKEND_URL=postgres://stem:stem@127.0.0.1:5432/stem_demo
export STEM_DEFAULT_QUEUE=reports
```

### 3. Run the worker

```bash
cd examples/postgres_worker/worker
dart pub get
dart run bin/worker.dart
```

The worker connects to Postgres, creates the required tables (if absent), and
waits for `report.generate` tasks on the `reports` queue.

### 4. Enqueue demo jobs

In a new terminal (with the same environment variables):

```bash
cd examples/postgres_worker/enqueuer
dart pub get
dart run bin/enqueue.dart
```

Three jobs (`us-east`, `eu-west`, `ap-south`) are published. The worker logs the
processing output and stores task results in Postgres.

### 5. Inspect Postgres (optional)

```bash
psql postgres://stem:stem@127.0.0.1:5432/stem_demo -c 'SELECT id,state,meta FROM stem_demo_task_results;'
```

### 6. Cleanup

Stop the worker (`Ctrl+C`) and bring down Postgres when finished:

```bash
docker compose -f docker-compose.yml down
```

---

This example uses the same APIs as production deployments; adjust connection
strings, TLS, and credentials to match your environment.

### Local build + Docker deps (just)

By default the Justfile loads `.env`. To use the sample settings, either copy `.env.example` to `.env` or pass `ENV_FILE=.env.example` and update hostnames to `localhost` for local runs.

```bash
just deps-up
just build
# In separate terminals:
just run-worker
just run-enqueuer
# Or:
just tmux
```
