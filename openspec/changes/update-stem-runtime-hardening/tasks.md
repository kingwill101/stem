## Tasks
- [ ] Update broker capability spec to cover queue purges clearing priority streams and tearing down background claim timers once a consumer stops.
- [ ] Update CLI health spec to require Postgres backends be checked alongside Redis and to surface backend-specific diagnostics.
- [ ] Update observability spec to mandate TLS support for Redis heartbeat transports.
- [x] Implement Redis broker fixes (priority stream purge + claim timer cleanup) with accompanying unit coverage.
- [x] Extend CLI health command to exercise Postgres result backend connectivity and add focused tests.
- [x] Add TLS-aware connection path to `RedisHeartbeatTransport` plus unit coverage using mocked redis command/socket interfaces.
- [ ] Add integration regression tests that run against services from `docker/testing/docker-compose.yml` validating purge behaviour, claim timer shutdown, and cross-backend health checks.
- [x] Document and script the docker-backed test run so CI and contributors can reproduce the integration results locally.
- [ ] Run `dart format`, `dart analyze`, targeted unit suites, and the docker-backed integration tests to confirm the fixes.
