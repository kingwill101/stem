<file_path>
untitled6/examples/image_processor/README.md
</file_path>

<edit_description>
Create README.md for image processor example
</edit_description>

# Stem Image Processor Example

This example demonstrates image thumbnail generation using Stem. It enqueues image processing tasks, handles downloads and resizing, with retries for failures.

## Prerequisites

- Docker and Docker Compose
- Dart 3.3+ (optional, only required for manual runs)

## Configuration

Environment variables:

| Variable | Default (Docker) | Description |
| --- | --- | --- |
| `STEM_BROKER_URL` | `redis://redis:6379/0` | Redis Streams broker connection string. |
| `STEM_RESULT_BACKEND_URL` | `redis://redis:6379/1` | Redis result backend connection string. |
| `PORT` | `8083` | Port for the HTTP API. |
| `OUTPUT_DIR` | `/tmp/thumbnails` | Directory where thumbnails are written inside the worker container. |

Copy `.env.example` to `.env` before running with Docker.

## Running with Docker Compose

```bash
cd examples/image_processor
cp .env.example .env # optional override
docker compose up --build
```

This starts Redis, the thumbnail worker, and the API service. The API is available at `http://localhost:8083`.

Submit a job:

```bash
curl -X POST http://localhost:8083/process-image \
  -H 'content-type: application/json' \
  -d '{"imageUrl": "https://picsum.photos/600"}'
```

Generated thumbnails are written to the directory specified by `OUTPUT_DIR` (inside the worker container or locally when running with Dart).

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
   export OUTPUT_DIR=
   ```

3. Run the worker and API in separate terminals using `dart pub get` / `dart run`.

This example demonstrates offloading I/O heavy work, retry semantics, and sharing metadata between the API and worker through the result backend.
