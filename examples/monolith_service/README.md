# Stem Monolith Example

A minimal single-process deployment that exposes an HTTP API for enqueuing greeting tasks, executes them with an in-process worker, and stores task state in the in-memory backend.

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

This example uses in-memory adapters, making it ideal for local experimentation or integration tests.

## Cleanup

Press `Ctrl+C` in the service terminal to shut down the worker and HTTP server.
