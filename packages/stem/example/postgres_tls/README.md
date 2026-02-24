# Postgres TLS Example

This sample shows how to run Stem with a Redis broker and a Postgres result
backend secured with TLS. Stem consumes the standard `STEM_TLS_*` environment
variables to build libpq connection parameters so the same certificate bundle
can be reused across brokers and backends.

## Prerequisites

- Docker (for the bundled Postgres + Redis services)
- Dart 3.9 or newer (`dart --version`)

## Run the demo

1. Start Redis + Postgres(TLS):
   ```bash
   task deps-up
   ```
2. Export the environment expected by the scripts:
   ```bash
   export STEM_BROKER_URL=redis://127.0.0.1:${REDIS_PORT:-6379}
   export STEM_RESULT_BACKEND_URL=postgresql://postgres:postgres@127.0.0.1:${POSTGRES_PORT:-5432}/stem_test
   export STEM_TLS_CA_CERT=../../../stem_cli/docker/testing/certs/postgres-root.crt
   ```
3. Compile binaries:
   ```bash
   task build
   ```
4. In one shell, run the worker:
   ```bash
   task run:worker
   ```
5. In another shell, enqueue a few tasks:
   ```bash
   task run:enqueue
   ```
6. Watch the worker log the envelopes. TLS handshake failures will surface the
   CA path, `allowInsecure` flag, and libpq diagnostics to speed up debugging.

Stop the containers when you're done:
```bash
task deps-down
```
