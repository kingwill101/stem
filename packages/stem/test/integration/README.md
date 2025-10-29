# Integration Tests

These suites exercise brokers, backends, and scheduler components against real
services. They **require** Postgres and Redis endpoints to be accessible via
environment variables:

```bash
export STEM_TEST_POSTGRES_URL=postgres://postgres:postgres@127.0.0.1:65432/stem_test
export STEM_TEST_REDIS_URL=redis://127.0.0.1:56379/0
```

You can start local instances with the Docker compose file that now lives in the
CLI package:

```bash
docker compose -f packages/stem_cli/docker/testing/docker-compose.yml up -d
```

The repository also provides `source packages/stem_cli/_init_test_env`, which
starts the same stack and exports the `STEM_TEST_*` environment variables required
by the integration suites.

Integration suites have moved alongside their adapters:

- `packages/stem_redis/test/integration/**`
- `packages/stem_postgres/test/integration/**`
- `packages/stem_cli/test/integration/**`

Run them individually, for example:

```bash
dart test packages/stem_redis/test/integration
dart test packages/stem_postgres/test/integration
dart test packages/stem_cli/test/integration
```

## Runtime Hardening Suites

- `packages/stem_redis/test/integration/brokers/redis_broker_integration_test.dart`
  exercises Redis queue purging across priority streams and validates claim timer
  shutdown using the dockerised Redis instance.
- `packages/stem_cli/test/integration/cli/cli_health_integration_test.dart`
  verifies that `stem health` reports Postgres/Redis backend connectivity against
  the docker stack.

Each suite will `skip` automatically if the required environment variables are
missing. Use these tests for manual verification; they are not intended for the
standard unit-test pipeline.
