# Stem Monolith Example

A minimal single-process deployment that exposes an HTTP API for enqueuing greeting tasks, executes them with an in-process worker, runs the Beat scheduler, and stores task state in the in-memory backend.

## Configuration

The service reads the following environment variables:

| Variable | Default | Description |
| --- | --- | --- |
| `PORT` | `8080` | HTTP listen port for the REST API. |

Copy `.env.example` to `.env` (or export variables manually) when using Docker.

## Running locally

```bash
cd examples/monolith_service
dart pub get
dart run bin/service.dart
```

In another terminal, enqueue a task:

```bash
curl -X POST http://localhost:8080/enqueue \
  -H 'content-type: application/json' \
  -d '{"name": "Ada"}'
```

Fetch task status:

```bash
curl http://localhost:8080/status/<taskId>
```

Queue a fan-out job using the canvas helpers:

```bash
curl -X POST http://localhost:8080/group \
  -H 'content-type: application/json' \
  -d '{"names": ["Ada", "Perseverance", "Curiosity"]}'
```

Inspect the group results:

```bash
curl http://localhost:8080/group/<groupId>
```

The Beat scheduler also dispatches the `demo-greeting` schedule every 30 seconds,
which you can observe in the worker logs.

This example uses in-memory adapters, making it ideal for local experimentation or integration tests.

## Running with Docker

Build the container from the repository root:

```bash
docker build -f examples/monolith_service/Dockerfile -t stem-monolith .
```

Run it (optionally overriding the port):

```bash
docker run --rm -p 8080:8080 --env-file examples/monolith_service/.env.example stem-monolith
```

The HTTP API is now available at `http://localhost:8080`.

## Cleanup

Press `Ctrl+C` in the service terminal (or `docker stop` the container) to shut down the worker and HTTP server.
