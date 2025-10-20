# Stem Microservice Example

This example splits the enqueue API and worker into separate Dart packages communicating through Redis Streams.

## Prerequisites

- Docker and Docker Compose
- Dart 3.3+ (optional, only needed for running directly on your machine)

## Configuration

All services expect the following environment variables:

| Variable | Default (Docker) | Description |
| --- | --- | --- |
| `STEM_BROKER_URL` | `redis://redis:6379/0` | Redis Streams broker connection string. |
| `STEM_RESULT_BACKEND_URL` | `redis://redis:6379/1` | Redis result backend connection string. |
| `STEM_SIGNING_KEYS` | `primary:<base64 secret>` | Comma-separated list of `keyId:base64Secret` pairs accepted by workers. |
| `STEM_SIGNING_ACTIVE_KEY` | `primary` | Key id used by enqueuers to sign new envelopes. |
| `PORT` | `8081` | HTTP port for the enqueue API. |

Copy `.env.example` to `.env` and adjust values as needed when using Docker.

Generate a fresh signing secret before production use:

```bash
openssl rand -base64 32
# or ./scripts/security/generate_tls_assets.sh to create TLS assets as well
```
Replace the placeholder secret in `.env` with the generated value and update `STEM_SIGNING_ACTIVE_KEY` when rotating keys.

## Running with Docker Compose

```bash
cd examples/microservice
cp .env.example .env # optional override
docker compose up --build
```

This launches Redis, the worker, and the enqueue API. The API is reachable at `http://localhost:8081`.

Enqueue a task:

```bash
curl -X POST http://localhost:8081/enqueue \
  -H 'content-type: application/json' \
  -d '{"name": "Ada"}'
```

Stop the stack with `docker compose down`.

## Running locally with Dart

1. Start Redis:

   ```bash
   docker compose up -d redis
   ```

2. Export the environment variables:

   ```bash
   export STEM_BROKER_URL=redis://localhost:6379/0
   export STEM_RESULT_BACKEND_URL=redis://localhost:6379/1
   export STEM_SIGNING_KEYS=primary:$(openssl rand -base64 32)
   export STEM_SIGNING_ACTIVE_KEY=primary
   ```

3. Run the worker:

   ```bash
   cd examples/microservice/worker
   dart pub get
   dart run bin/worker.dart
   ```

4. In another terminal, run the enqueue API:

   ```bash
   cd examples/microservice/enqueuer
   dart pub get
   dart run bin/main.dart
   ```

The worker logs progress for each greeting task, demonstrating isolate execution, heartbeats, and result backend updates.
