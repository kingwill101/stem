## Overview
We will ship a dedicated testing package that adapter implementations can depend on (dev-only) to run a consistent contract suite. The package exposes helper APIs to construct tests around user-supplied factories for brokers and result backends. The suite will drive the core contract flows defined in `Broker` and `ResultBackend`, such as enqueue/consume acknowledgements, dead-letter replay, lease extension, TTL pruning, group aggregation, and heartbeat persistence.

## Package Layout
- `lib/broker_contract_tests.dart`: exposes a `runBrokerContractTests` function requiring factories for broker instances, queue names, and optional clean-up hooks. The suite verifies publish/consume, ack/nack, dead-letter behaviour, purge, lease expiry via a synthetic clock, and delayed delivery semantics.
- `lib/result_backend_contract_tests.dart`: exports `runResultBackendContractTests` accepting factories for new backend instances and TTL configuration overrides. Scenarios cover status persistence, streaming watchers, TTL expiry, group aggregation, and worker heartbeat listing/removal.
- `lib/support/test_clock.dart`: optional utilities to manipulate timeouts when the adapter supports injecting a clock.

## Adapter Integration
- Each adapter package adds a dev-dependency on the new package and invokes the contract runners inside its own test suite, supplying adapter-specific factories (e.g., Redis connection URIs, temporary file paths).
- The harness returns a `Group` so adapters can inject additional setup/teardown logic (e.g., Docker fixtures, pre-test migrations).
- Existing bespoke contract tests in `packages/stem/test/integration/brokers` and `packages/stem/test/integration/backends` will be migrated to call the shared suite to avoid duplication while preserving adapter-specific cases.

## Open Questions
- Some adapters (Redis) require external services; the harness will accept async `setUp` hooks so callers can provide environment variables or skip suites when dependencies are unavailable.
- SQLite adapters may need to override lease polling intervals; the API will allow optional configuration parameters passed through to the factory.
