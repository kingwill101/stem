# Mixed Redis/Postgres Cluster Example

This example runs two independent workers side by side:

- **Redis worker** – uses Redis Streams as both broker and result backend.
- **Postgres worker** – uses Postgres for broker and result backend.

A single enqueuer publishes demo jobs to each queue so you can see both workers
consuming concurrently.

## Docker Compose quick start

1. Copy the environment template:

   ```bash
   cp .env.example .env
   ```

2. Start Redis, Postgres, both workers, and the enqueuer:

   ```bash
   docker compose up --build redis_worker postgres_worker enqueuer
   ```

   The enqueuer publishes a few demo jobs and exits (Compose restarts it by
   default). Watch the worker logs to see each subsystem processing tasks.

3. When finished, shut everything down:

   ```bash
   docker compose down
   ```

## Manual workflow

1. Start dependencies:

   ```bash
   docker compose up redis postgres -d
   ```

2. Export environment variables for each worker:

   ```bash
   export REDIS_STEM_BROKER_URL=redis://127.0.0.1:6379/0
   export REDIS_STEM_RESULT_BACKEND_URL=redis://127.0.0.1:6379/1
   export REDIS_STEM_DEFAULT_QUEUE=redis-tasks

   export POSTGRES_STEM_BROKER_URL=postgres://stem:stem@127.0.0.1:5432/stem_demo
   export POSTGRES_STEM_RESULT_BACKEND_URL=postgres://stem:stem@127.0.0.1:5432/stem_demo
   export POSTGRES_STEM_DEFAULT_QUEUE=postgres-tasks
   ```

3. Run the Redis worker:

   ```bash
   cd examples/mixed_cluster/redis_worker
   dart pub get
   STEM_BROKER_URL=$REDIS_STEM_BROKER_URL \
   STEM_RESULT_BACKEND_URL=$REDIS_STEM_RESULT_BACKEND_URL \
   STEM_DEFAULT_QUEUE=$REDIS_STEM_DEFAULT_QUEUE \
   dart run bin/worker.dart
   ```

4. In another terminal, run the Postgres worker:

   ```bash
   cd examples/mixed_cluster/postgres_worker
   dart pub get
   STEM_BROKER_URL=$POSTGRES_STEM_BROKER_URL \
   STEM_RESULT_BACKEND_URL=$POSTGRES_STEM_RESULT_BACKEND_URL \
   STEM_DEFAULT_QUEUE=$POSTGRES_STEM_DEFAULT_QUEUE \
   dart run bin/worker.dart
   ```

5. Enqueue demo jobs:

   ```bash
   cd examples/mixed_cluster/enqueuer
   dart pub get
   REDIS_STEM_BROKER_URL=$REDIS_STEM_BROKER_URL \
   REDIS_STEM_RESULT_BACKEND_URL=$REDIS_STEM_RESULT_BACKEND_URL \
   REDIS_STEM_DEFAULT_QUEUE=$REDIS_STEM_DEFAULT_QUEUE \
   POSTGRES_STEM_BROKER_URL=$POSTGRES_STEM_BROKER_URL \
   POSTGRES_STEM_RESULT_BACKEND_URL=$POSTGRES_STEM_RESULT_BACKEND_URL \
   POSTGRES_STEM_DEFAULT_QUEUE=$POSTGRES_STEM_DEFAULT_QUEUE \
   dart run bin/enqueue.dart
   ```

6. Cleanup:

   ```bash
   docker compose down
   ```

This setup mirrors a deployment where different workloads use different brokers
and backends while sharing the same Stem codebase.

### Local build + Docker deps (just)

By default the Justfile loads `.env`. To use the sample settings, either copy `.env.example` to `.env` or pass `ENV_FILE=.env.example` and update hostnames to `localhost` for local runs.

```bash
just deps-up
just build
# In separate terminals:
just run-redis-worker
just run-postgres-worker
just run-enqueuer
# Or:
just tmux
```
