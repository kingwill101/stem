## Why
- Coverage runs can still hide failures because chaos tests only run against the in-memory broker.
- Quality tooling exists locally but is not guaranteed in CI, so regressions can slip through.

## What Changes
- Add configuration to run chaos tests against a real Redis instance and document how to target it locally/CI.
- Extend the CI workflow to run the quality script and chaos suite on a Redis service.
- Update docs/specs to capture the new guarantees.

## Impact
- CI runtime will increase while chaos tests execute against Redis.
- Requires a Redis service in CI runners (Docker service or container).
- Contributors may need Docker available locally to reproduce the Redis chaos suite.
