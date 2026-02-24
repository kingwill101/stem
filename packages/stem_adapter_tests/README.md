# stem_adapter_tests

Shared contract suites for adapter packages. Use this package to prove your
broker, result backend, workflow store, and lock store semantics match Stem's
runtime expectations.

## Install

```bash
dart pub add --dev stem_adapter_tests
```

## Quick Start

```dart
import 'package:stem_adapter_tests/stem_adapter_tests.dart';

void main() {
  runBrokerContractTests(
    adapterName: 'my-adapter',
    factory: BrokerContractFactory(create: createBroker),
  );

  runResultBackendContractTests(
    adapterName: 'my-adapter',
    factory: ResultBackendContractFactory(create: createBackend),
  );

  runQueueEventsContractTests(
    adapterName: 'my-adapter',
    factory: QueueEventsContractFactory(create: createBroker),
  );

  final workflowFactory = WorkflowStoreContractFactory(
    create: createWorkflowStore,
  );

  runWorkflowStoreContractTests(
    adapterName: 'my-adapter',
    factory: workflowFactory,
  );

  runWorkflowScriptFacadeTests(
    adapterName: 'my-adapter',
    factory: workflowFactory,
  );
}
```

## Capability Flags

Capability flags let adapters opt out of specific behavior checks while keeping
all other contract assertions active.

### BrokerContractCapabilities

| Flag | Default | Affects | Behavior when enabled |
|---|---|---|---|
| `verifyPriorityOrdering` | `true` | Broker priority test group | Verifies higher-priority messages are delivered first. |
| `verifyBroadcastFanout` | `false` | Broadcast fan-out test group | Verifies broadcast delivery reaches all subscribers and replay semantics remain correct. |

### ResultBackendContractCapabilities

| Flag | Default | Affects | Behavior when enabled |
|---|---|---|---|
| `verifyTaskStatusExpiry` | `true` | Task status expiry tests | Verifies status TTL expiration behavior. |
| `verifyGroupExpiry` | `true` | Group expiry tests | Verifies group TTL expiration and post-expiry behavior. |
| `verifyChordClaiming` | `true` | Chord claiming tests | Verifies single-claimant callback dispatch semantics. |
| `verifyWorkerHeartbeats` | `true` | Heartbeat CRUD tests | Verifies heartbeat set/get/list/update behavior. |
| `verifyHeartbeatExpiry` | `true` | Heartbeat expiry tests | Verifies heartbeat TTL expiration behavior independently from heartbeat CRUD checks. |

### QueueEventsContractCapabilities

| Flag | Default | Affects | Behavior when enabled |
|---|---|---|---|
| `verifyFanout` | `true` | Multi-listener fan-out tests | Verifies custom queue events reach all active listeners on the same queue scope. |

### WorkflowStoreContractCapabilities

| Flag | Default | Affects | Behavior when enabled |
|---|---|---|---|
| `verifyVersionedCheckpoints` | `true` | Checkpoint versioning tests | Verifies versioned checkpoint persistence and retrieval. |
| `verifyRunLeases` | `true` | Run lease tests | Verifies claim/renew/release lease semantics. |
| `verifyWatcherRegistry` | `true` | Watcher tests | Verifies watcher registration, listing, and resolution behavior. |
| `verifyRunsWaitingOn` | `true` | Waiting-topic lookup tests | Verifies lookups for runs waiting on external topics. |
| `verifyFilteredRunListing` | `true` | Filtered run listing tests | Verifies filtered listing and pagination semantics. |

### LockStoreContractCapabilities

| Flag | Default | Affects | Behavior when enabled |
|---|---|---|---|
| `verifyOwnerLookup` | `true` | `ownerOf` tests | Verifies lock owner lookup behavior. |
| `verifyRenewSemantics` | `true` | Renew and expiry tests | Verifies renewal/TTL semantics for active locks. |

## Skip Behavior

Each flagged test uses explicit `skip` values (instead of implicit omission) so
it is always clear which capability disabled a test and why.

## Adapter Recipes

### Full-feature adapter

```dart
runResultBackendContractTests(
  adapterName: 'full-adapter',
  factory: ResultBackendContractFactory(create: createBackend),
  settings: const ResultBackendContractSettings(
    capabilities: ResultBackendContractCapabilities(),
  ),
);
```

### Adapter without broadcast fan-out

```dart
runBrokerContractTests(
  adapterName: 'queue-only-adapter',
  factory: BrokerContractFactory(create: createBroker),
  settings: const BrokerContractSettings(
    capabilities: BrokerContractCapabilities(
      verifyBroadcastFanout: false,
    ),
  ),
);
```

### Adapter with heartbeat CRUD but no heartbeat expiry

```dart
runResultBackendContractTests(
  adapterName: 'no-heartbeat-expiry-adapter',
  factory: ResultBackendContractFactory(create: createBackend),
  settings: const ResultBackendContractSettings(
    capabilities: ResultBackendContractCapabilities(
      verifyWorkerHeartbeats: true,
      verifyHeartbeatExpiry: false,
    ),
  ),
);
```

## Workflow Clock Requirement

Workflow store factories receive a shared `FakeWorkflowClock`. Inject that same
clock into your runtime/store under test so workflow facade and store assertions
observe the same deterministic timeline.

## Versioning

This package tracks the same release cadence as `stem`.
