## Why
- Redis adapters honour `STEM_TLS_*` for secure connections, but the Postgres result backend ignores those settings; operators must handcraft libpq parameters instead.
- We also lack a regression test that validates signed envelopes survive Postgres when TLS is active.
- Unifying TLS handling across backends reduces configuration drift and ensures secure-by-default deployments.

## What Changes
- Extend `PostgresClient` (and StemConfig) to consume `STEM_TLS_*` values, building the appropriate connection options.
- Document the behaviour and add integration coverage running against a TLS-enabled Postgres instance.
- Confirm signed envelope metadata still round-trips over TLS.

## Impact
- Operators configure TLS once via environment variables for both Redis and Postgres backends.
- Improves security posture for production deployments without changing existing non-TLS behaviour.
- Requires CI/docker updates to provide a TLS-enabled Postgres for integration tests.
