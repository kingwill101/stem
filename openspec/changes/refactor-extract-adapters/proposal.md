## Why
Redis and Postgres adapters still live inside the core `stem` package. That coupling forces the
core to depend on adapter SDKs and keeps the CLI/operations tooling tied to a monolithic package.
We want the core to stay lightweight while adapters and CLI can evolve independently.

## What Changes
- Extract Redis-specific broker, backend, scheduler, control utilities, examples, and tests into a
  new `stem_redis` package that depends on `stem`.
- Extract Postgres-specific broker, backend, scheduler, control utilities, migrations, examples,
  and tests into a new `stem_postgres` package that depends on `stem`.
- Move the Stem CLI and docker-based integration harness into a new `stem_cli` package that depends
  on the adapter packages instead of the core.
- Update the remaining `stem` package to expose only core contracts, in-memory adapters, and shared
  components that do not require Redis/Postgres.
- Ensure workspace metadata, README references, and CI/test scripts point to the new package
  locations.

## Impact
- Affected specs: core runtime modularity, adapter packaging (new capability docs forthcoming).
- Affected code: most Redis/Postgres files under `packages/stem/lib`, CLI entrypoint, integration
  tests, examples, docker helper scripts, workspace manifests.
- Potential breaking change: downstream users must add explicit dependencies on `stem_redis`,
  `stem_postgres`, or `stem_cli` once published.
