## Stem

Stem is a spec-driven background job platform for Dart. It provides task
registration, Redis Streams integration, isolate-aware workers, retries, a beat
scheduler, CLI tooling for observability and dead-letter remediation, plus
Postgres adapters for result persistence and schedule coordination.

### Highlights

- At-least-once delivery semantics with configurable retry strategies.
- Isolate pool execution with soft and hard time limits.
- Redis Streams broker (plus in-memory adapters for tests).
- Result backends backed by Redis **or Postgres**, including group/chord primitives.
- Schedule stores backed by Redis **or Postgres** with distributed locking.
- CLI support for schedules, observability snapshots, and DLQ replay.
- OpenTelemetry metrics and heartbeat events.

### Documentation

The documentation site lives in `.site/`.

```bash
cd .site
npm install
npm start
```

Quick links:

- [Quick Start](.site/docs/quick-start.md)
- [Developer Guide](.site/docs/developer-guide.md)
- [Operations Guide](.site/docs/operations-guide.md)
- [Broker Comparison](.site/docs/broker-comparison.md)
- [Release Process](.site/docs/release-process.md)

### Compatibility

Stem follows semantic versioning. Public interfaces (`Broker`, `ResultBackend`,
`ScheduleStore`, etc.) are marked as stable starting from `0.1.0`; breaking
changes will only occur with a major version bump. See the release process doc
for details.

| Component | Supported versions / notes |
| --- | --- |
| Dart SDK | 3.9.2 and newer |
| Platforms | Linux and macOS verified via CI; Windows support is experimental |
| TLS dependencies | LibreSSL/OpenSSL available on the host for `rediss://` connections |
| Redis | 7.x (Streams, XAUTOCLAIM, RediSearch not required) |

When enabling TLS, set `STEM_TLS_CA_CERT`, `STEM_TLS_CLIENT_CERT`, and
`STEM_TLS_CLIENT_KEY` as needed. Handshake failures log the endpoint, TLS
options, and suggest using `STEM_TLS_ALLOW_INSECURE=true` temporarily while
debugging.

### Quality Suite

Run formatting, analysis, tests, and coverage with:

```bash
tool/quality/run_quality_checks.sh
```

Set `RUN_COVERAGE=0` to skip coverage locally or override the threshold (default
60%) with `COVERAGE_THRESHOLD`. Provide `STEM_CHAOS_REDIS_URL` (for example,
`redis://127.0.0.1:6379/15`) to run the chaos suite against a real Redis instance.
A disposable Redis suitable for chaos tests can be launched with:

```bash
docker compose -f scripts/docker/redis-chaos.yml up -d
```

Long-running soak tests are tagged and can be executed
explicitly:

```bash
dart test --tags soak
```

See `docs/process/testing.md` for the full testing and CI workflow.

#### Integration Tests

Integration suites live under `test/integration/` and exercise brokers,
backends, and the scheduler against real services. A convenience Compose file
spins up the required Postgres and Redis instances:

```bash
docker compose -f docker/testing/docker-compose.yml up -d
export STEM_TEST_POSTGRES_URL=postgres://postgres:postgres@127.0.0.1:65432/stem_test
export STEM_TEST_REDIS_URL=redis://127.0.0.1:56379/0
dart test test/integration
docker compose -f docker/testing/docker-compose.yml down
```

Each suite skips automatically when the corresponding environment variable is
unset, so CI jobs can opt in selectively.

### Examples

Three runnable example apps demonstrate common topologies:

- `examples/monolith_service` – single process service using in-memory adapters.
- `examples/microservice` – enqueue API and worker communicating through Redis.
- `examples/postgres_worker` – broker and result backend backed by Postgres.
- `examples/redis_postgres_worker` – Redis Streams broker with a Postgres result backend.
- `examples/mixed_cluster` – runs Redis- and Postgres-backed workers side by side.
- `examples/encrypted_payload` – encrypt task payloads end-to-end with AES-GCM (includes a containerized variant in `docker/`).
- `examples/otel_metrics` – worker + OpenTelemetry collector + Jaeger via Docker Compose.

Each example has a README with setup instructions and links back to the docs.

### CLI Quick Reference

```bash
stem schedule list
stem observe metrics
stem dlq list --queue default --limit 20
stem dlq replay --queue default --limit 10 --yes
stem health
stem worker ping --namespace stem
stem worker inspect --worker worker-1
stem worker stats --namespace stem
stem worker revoke --task <task-id> [--terminate]
```

See `docs/process/worker-control.md` for detailed control-plane usage,
including revoke persistence and termination behavior.

### Security Utilities

- Generate mutual TLS assets for Redis/HTTP services:

  ```bash
  scripts/security/generate_tls_assets.sh certs stem.local,redis,api.localhost
  ```

  Mount `ca.crt`, `server.crt/server.key`, and `client.crt/client.key` into
  services and configure `STEM_TLS_*` (plus `ENQUEUER_TLS_*` for HTTPS) to refuse
  plaintext connections.
  - `server.crt`/`server.key` stay with Redis and the HTTPS enqueuer service to
    terminate TLS and assert identity.
  - `client.crt`/`client.key` are mounted by Stem producers/workers so Redis can
    enforce mutual TLS.
  - `ca.crt` is distributed to every client via `STEM_TLS_CA_CERT` (and
    `ENQUEUER_TLS_CLIENT_CA`) so certificate validation remains enabled.

- Run recurring Trivy scans:

  ```bash
  scripts/security/run_vulnerability_scan.sh
  ```

  High/Critical findings are triaged by the on-call security owner via the
  scheduled `security-scan.yml` workflow.

See `openspec/changes/` for the spec deltas that drive the implementation. Pull
requests should include updated specs and passing `openspec validate --strict`,
`dart format`, and `dart test` runs.
