# Postgres TLS Example

This sample shows how to run Stem with a Redis broker and a Postgres result
backend secured with TLS. Stem consumes the standard `STEM_TLS_*` environment
variables to build libpq connection parameters so the same certificate bundle
can be reused across brokers and backends.

## Prerequisites

- Docker (for the bundled Postgres + Redis services)
- Dart 3.9 or newer (`dart --version`)

## Run the demo

1. Start the test services with TLS enabled:
   ```bash
   docker compose -f ../../stem_cli/docker/testing/docker-compose.yml up postgres redis -d
   ```
2. Export the environment expected by the scripts:
   ```bash
   export STEM_BROKER_URL=redis://127.0.0.1:56379
   export STEM_RESULT_BACKEND_URL=postgresql://postgres:postgres@127.0.0.1:65432/stem_test
   export STEM_TLS_CA_CERT=../../stem_cli/docker/testing/certs/postgres-root.crt
   # Optional: allow verification bypass during CA troubleshooting
   # export STEM_TLS_ALLOW_INSECURE=true
   ```
3. In one shell, run the worker:
   ```bash
   dart run example/postgres_tls/bin/worker.dart
   ```
4. In another shell, enqueue a few tasks:
   ```bash
   dart run example/postgres_tls/bin/enqueue.dart
   ```
5. Watch the worker log the envelopes. TLS handshake failures will surface the
   CA path, `allowInsecure` flag, and libpq diagnostics to speed up debugging.

Stop the containers when you're done:
```bash
docker compose -f ../../stem_cli/docker/testing/docker-compose.yml down
```
