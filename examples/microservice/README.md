# Stem Microservice Example

This example splits the enqueue API and worker into separate Dart packages communicating through Redis Streams.

## Prerequisites

- Docker (for Redis)
- Dart 3.3+

## Getting started

1. Start Redis:

   ```bash
   cd examples/microservice
   docker compose up -d redis
   ```

2. Export the Stem environment variables (use the same values for both services):

   ```bash
   export STEM_BROKER_URL=redis://localhost:6379/0
   export STEM_RESULT_BACKEND_URL=redis://localhost:6379/1
   ```

3. Run the worker:

   ```bash
   cd worker
   dart pub get
   dart run bin/worker.dart
   ```

4. In another terminal, start the enqueue API:

   ```bash
   cd examples/microservice/enqueuer
   dart pub get
   dart run bin/main.dart
   ```

5. Enqueue a task:

   ```bash
   curl -X POST http://localhost:8081/enqueue \
     -H 'content-type: application/json' \
     -d '{"name": "Ada"}'
   ```

6. Inspect task status via Redis or the `stem dlq` / observability commands.

## Shutdown

- Press `Ctrl+C` in both terminals to stop the services.
- Tear down Redis if desired: `docker compose down`.

The worker process logs progress for each greeting task, demonstrating isolate execution, heartbeats, and result backend updates.
