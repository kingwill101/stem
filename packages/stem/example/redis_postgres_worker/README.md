# Redis + Postgres Hybrid Example

This example wires Redis Streams as the broker and Postgres as the result
backend. It demonstrates a common hybrid topology: Redis handles transport and
leases, while Postgres stores task metadata and group results.

## Docker Compose quick start

1. Copy the environment template if you want to customise connection strings:

   ```bash
   cp .env.example .env
   ```

2. Start Redis, Postgres, the enqueuer, and the worker:

   ```bash
   docker compose up --build worker enqueuer
   ```

   The enqueuer publishes a few demo tasks and exits (Compose restarts it by
   default). Tail the worker logs to see processing events.

3. Stop everything when finished:

   ```bash
   docker compose down
   ```

## Manual workflow

1. Start dependencies:

   ```bash
   docker compose up redis postgres -d
   ```

2. Export Stem environment variables:

   ```bash
   export STEM_BROKER_URL=redis://127.0.0.1:6379/0
   export STEM_RESULT_BACKEND_URL=postgres://stem:stem@127.0.0.1:5432/stem_demo
   export STEM_DEFAULT_QUEUE=hybrid
   ```

3. Run the worker:

   ```bash
   cd examples/redis_postgres_worker/worker
   dart pub get
   dart run bin/worker.dart
   ```

4. Enqueue demo jobs in another terminal:

   ```bash
   cd examples/redis_postgres_worker/enqueuer
   dart pub get
   dart run bin/enqueue.dart
   ```

5. Inspect Postgres (optional):

   ```bash
   psql postgres://stem:stem@127.0.0.1:5432/stem_demo \
     -c 'SELECT id,state,meta FROM stem_demo_task_results;'
   ```

6. Cleanup:

   ```bash
   docker compose down
   ```

The code uses the same APIs as production deployments; adapt configuration to
match your environment (TLS, credentials, namespaces, etc.).

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
