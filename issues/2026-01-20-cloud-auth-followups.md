# Cloud auth follow-ups (2026-01-20)

## Open items

- [ ] Cloud gateway tests require Postgres; document local setup or add a helper to bootstrap the DB before `dart test packages/cloud/stem_cloud_gateway/test`.
- [ ] `packages/cloud/stem_cloud_gateway/test/migrations_test.dart` expects 12 migrations but now loads 15; update the test expectation or reconcile migration registration.
