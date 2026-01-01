# Stem Microservice Example

This example splits the enqueue API, worker fleet, and beat scheduler into separate Dart packages communicating through Redis Streams.

## Prerequisites

- Docker and Docker Compose
- Dart 3.3+ (optional, only needed for running directly on your machine)

## Configuration

All services expect the following environment variables (see `.env.example` for defaults used by `docker compose`):

| Variable | Default (Docker) | Description |
| --- | --- | --- |
| `STEM_BROKER_URL` | `redis://redis:6379/0` | Redis Streams broker connection string. |
| `STEM_RESULT_BACKEND_URL` | `redis://redis:6379/1` | Redis result backend connection string. |
| `STEM_SCHEDULE_STORE_URL` | `redis://redis:6379/2` | Schedule/lock store consumed by the beat service. |
| `STEM_SIGNING_KEYS` | `primary:<base64 secret>` | Comma-separated list of `keyId:base64Secret` pairs accepted by workers. |
| `STEM_SIGNING_ACTIVE_KEY` | `primary` | Key id used by enqueuers to sign new envelopes. |
| `STEM_TLS_CA_CERT` | _(optional)_ | CA bundle trusted by clients (provide when enabling TLS manually). |
| `STEM_TLS_CLIENT_CERT` | _(optional)_ | mTLS client certificate used by enqueuers/workers. |
| `STEM_TLS_CLIENT_KEY` | _(optional)_ | Private key associated with the client certificate. |
| `PORT` | `8081` | HTTP port for the enqueue API (nginx fronts it on `api.localhost:8080`). |
| `STEM_SCHEDULE_FILE` | `/config/schedules.yaml` | Optional YAML file the beat service uses to seed schedules. |
| `STEM_METRIC_EXPORTERS` | `otlp:http://otel-collector:4318/v1/metrics` | Comma-separated list of metrics exporters enabled for workers (OTLP by default). |
| `STEM_OTLP_ENDPOINT` | `http://otel-collector:4318/v1/traces` | Default OTLP endpoint used when exporters do not specify a destination. |

Several ready-made security profiles live alongside this README:

- `.env.hmac` – HMAC signing without TLS (local development, default stack)
- `.env.hmac_tls` – HMAC signing with TLS-enabled Redis (optional)
- `.env.ed25519_tls` – Ed25519 signing with TLS-enabled Redis (optional)

Copy the variant you want to `.env` before starting the stack and adjust values as needed. The [Security Configuration Examples](../../docs/process/security-examples.md) page walks through each option step by step.

Generate a fresh signing secret before production use:

```bash
openssl rand -base64 32
# or ./scripts/security/generate_tls_assets.sh to create TLS assets as well (optional)
```
Replace the placeholder secret in `.env` with the generated value and update `STEM_SIGNING_ACTIVE_KEY` when rotating keys.

To migrate to Ed25519 signing (public/private), run:

```bash
dart run ../../scripts/security/generate_ed25519_keys.dart
```

and copy the printed environment variables into your `.env` file.

### Optional: Enabling TLS for Redis

If you want to run the stack with TLS enabled, generate certificates and switch your `.env` to one of the TLS profiles (`.env.hmac_tls`, `.env.ed25519_tls`). After updating the environment variables (including `STEM_BROKER_URL=rediss://...` and certificate paths), update `docker-compose.yml` to mount the certs and add the Redis TLS flags described in the comments.

## Running with Docker Compose

```bash
cd examples/microservice
cp .env.hmac_tls .env   # or .env.hmac / .env.ed25519_tls
docker compose up --build
```

The stack now brings up Redis, the enqueue API, three workers, the beat scheduler, the Hotwire dashboard, and an OpenTelemetry toolchain (collector, Prometheus, Grafana, Jaeger) behind a single nginx gateway. Once the containers are healthy the following endpoints hang off `http://localhost:8080/`:

- Dashboard UI: <http://localhost:8080/>
- Enqueue API: <http://localhost:8080/api/>
- Grafana: <http://localhost:8080/grafana/> (admin/admin)
- Prometheus: <http://localhost:8080/prometheus/>
- Jaeger: <http://localhost:8080/jaeger/>
- OTLP ingest from the host: `http://localhost:4318` (HTTP) or `grpc://localhost:4317`

- **Local overrides:** The compose file expects a routed ecosystem checkout next to this repo (sibling directory at `../routed_ecosystem`) so the dashboard overrides resolve correctly. If your local path differs, update the `volumes` entries in `docker-compose.yml` accordingly.

Workers emit metrics to the collector via OTLP; Prometheus scrapes the collector and Grafana ships with a pre-provisioned datasource so you can build dashboards immediately. Jaeger receives spans published through the collector, allowing you to trace enqueue and worker execution paths without extra configuration.

Enqueue a task:

```bash
curl -X POST http://api.localhost:8080/enqueue \
  -H 'content-type: application/json' \
  -d '{"name": "Ada"}'
```

Fan out work with the canvas helper:

```bash
curl -X POST http://api.localhost:8080/group \
  -H 'content-type: application/json' \
  -d '{"names": ["Ada", "Perseverance", "Curiosity"]}'
```

Fetch aggregated results:

```bash
curl http://api.localhost:8080/group/<groupId>
```

The beat service seeds the `greetings-reminder` schedule from
`schedules.example.yaml`. Inspect its progress with:

```bash
stem schedule list
stem schedule dry-run --id greetings-reminder --count 3
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

   > Add TLS certificates and switch to `rediss://` URLs if you want to test the TLS profiles locally.

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

The worker logs progress for each greeting task, demonstrating isolate execution, heartbeats, and result backend updates. Start the beat service in a third terminal to dispatch scheduled jobs:

```bash
cd examples/microservice/beat
dart pub get
dart run bin/beat.dart
```

## Local build + Docker deps (just)

Pick an environment profile and set `ENV_FILE` (or copy one to `.env`):

```bash
cp .env.hmac .env
# or: ENV_FILE=.env.hmac just tmux
```

Start dependencies, build binaries, and run in tmux:

```bash
just deps-up
just build
just tmux
```

If you prefer separate terminals:

```bash
just run-worker
just run-enqueuer
just run-beat
```
