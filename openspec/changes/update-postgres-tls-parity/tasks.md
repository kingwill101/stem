## Tasks
- [x] Update Stem config loading to expose TLS options for Postgres connections.
- [x] Teach `PostgresClient` to build libpq connection parameters from `TlsConfig`.
- [x] Provision TLS-enabled Postgres in docker/testing and document setup.
- [x] Add integration test that connects via TLS, writes/reads signed envelopes, and asserts headers survive.
- [x] Run `dart analyze`, unit tests, and TLS integration tests.
