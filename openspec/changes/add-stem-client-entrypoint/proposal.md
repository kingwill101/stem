## Why
Provide a single Stem entrypoint that owns broker/backend/store configuration and can be passed into workers and workflow runtimes, mirroring Temporal’s Client + Worker pattern.

## What Changes
- Introduce `StemClient` as the primary entrypoint for configuring and accessing Stem runtimes.
- Add a client-backed worker API so workers receive the same shared configuration via `StemClient`.
- Provide default (local/in-memory or explicit URLs) and cloud-backed client implementations.
- Update examples and docs to use `StemClient`.

## Impact
- Affected specs: client-entrypoint (new capability)
- Affected code: `packages/stem`, `packages/stem_cli` examples, cloud gateway integration (client implementation)
