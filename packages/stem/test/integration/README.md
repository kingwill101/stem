# Integration Tests

These suites exercise brokers, backends, and scheduler components against real
services. They **require** Postgres and Redis endpoints to be accessible via
environment variables:

```bash
export STEM_TEST_POSTGRES_URL=postgres://postgres:postgres@127.0.0.1:65432/stem_test
export STEM_TEST_REDIS_URL=redis://127.0.0.1:56379/0
```

You can start local instances with the provided Docker compose file:

```bash
docker compose -f docker/testing/docker-compose.yml up -d
```

The repository also provides `source ./_init_test_env`, which starts the same
stack and exports the `STEM_TEST_*` environment variables required by the
integration suites.

Run all integration tests:

```bash
dart test test/integration
```

## Runtime Hardening Suites

- `test/integration/brokers/redis_broker_integration_test.dart` exercises Redis
  queue purging across priority streams and validates claim timer shutdown using
  the dockerised Redis instance.
- `test/integration/cli/cli_health_integration_test.dart` verifies that
  `stem health` reports Postgres/Redis backend connectivity against the docker
  stack.

Each suite will `skip` automatically if the required environment variables are
missing. Use these tests for manual verification; they are not intended for the
standard unit-test pipeline.
