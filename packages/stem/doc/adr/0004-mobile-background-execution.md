# ADR 0004: App-Owned Scheduling, Stem-Owned Background Execution

## Status

Accepted. Core `Worker.runUntilIdle` / `StemApp.runUntilIdle` implement
admission-bounded execution with safe draining. The Android example owns its
Workmanager integration. Native foreground-service/iOS hosting and automatic
expiration propagation remain platform-integration work. Neither the runner nor
SQLite persistence grants OS execution time.

## Context

Applications need to process durable Stem tasks while minimized. A Dart isolate
keeps CPU work off the UI isolate, but does not keep a mobile process alive.
Android and iOS decide when a background execution window is available.

Applications may already use the Flutter `workmanager` plugin, a native
foreground service, or an iOS background-task integration. Making Stem install
another scheduler would duplicate registrations, constraints, retry policy, and
application lifecycle ownership.

The Flutter packages have deliberately removed their custom worker message
protocol. Background support must not reintroduce that protocol or create a
second task-processing implementation.

## Decision

**The application owns OS scheduling; Stem owns execution of Stem tasks within
the execution window granted by that scheduler.**

| Owner | Responsibilities |
| --- | --- |
| Application / scheduler integration | Plugin initialization, callback registration, native configuration, permissions, foreground-service type, notifications, constraints, wakeup requests, and scheduler retry/rescheduling policy |
| `stem` | Task definitions, routing, claims, leases, execution, task retries, durable results, and the scheduler-neutral bounded runner |
| `stem_flutter` | Flutter-specific bootstrap and execution adaptation where necessary, without a WorkManager dependency |
| `stem_flutter_sqlite` | Flutter/Ormed initialization and local store configuration, without owning OS scheduling |

The app supplies the standard entrypoint required by its scheduler, such as
Workmanager's top-level callback dispatcher. That callback invokes the core
Stem runner. It must not implement Stem's consume/ack/retry protocol.

The runner belongs in core because the execution contract is not specific to
Flutter, Android, or WorkManager. Platform adapters translate lifecycle signals
and outcomes; they must reuse core execution semantics.

## Required execution contract

- Work on an explicitly selected queue/subscription using normal modules and
  durable store configuration.
- Stop admitting tasks before the execution budget expires, reserve time for
  orderly completion, and respond to cancellation when the platform exposes it.
- Preserve core acknowledgement, retry, lease, and shutdown behavior. A result
  write and a successful delivery acknowledgement are different lifecycle steps.
- Return an outcome describing why the invocation stopped, rather than a
  scheduler-specific boolean or a claim that every task succeeded.
- Leave deferred tasks in durable storage, without busy-waiting for their ETA.
- Release callback-owned resources before reporting completion to the scheduler.
- Handle abrupt termination through durable recovery, not by assuming Dart
  `finally` blocks always run.

Deadlines are not a promise to forcibly terminate arbitrary inline Dart code.
Heavy jobs must use an appropriate execution mode and checkpoint or split work
where needed. The platform may still cancel, suspend, or terminate execution.

The initial implementation stops admission on budget/cancellation and waits for
active delivery lifecycles and inline execution to quiesce before closing stores.
It does not inject revocations or promise that the requested shutdown reserve is
enough to finish every active handler. Idle detection is an observed quiet
period, not a global empty-queue guarantee.

Shutdown also joins child-isolate lifecycle hooks and outstanding lease-renewal
operations. Calling `shutdown` from a worker's own active task/lifecycle hook
is rejected with `StateError`, since waiting for the caller itself would
deadlock. Complete the caller-owned cancellation signal from such a hook and
let the external runtime owner await completion instead. Redundant normal
`start` calls from an active worker callback are no-ops, not readiness waits;
an external owner must await startup readiness.

## Alternatives considered

### Put WorkManager ownership in `stem_flutter`

Rejected as the default. It would make an adapter-neutral package choose
application scheduling and native policy, conflict with existing dispatchers,
and still fail to represent iOS and foreground-service lifecycles faithfully.

### Make every application implement its own Stem worker loop

Rejected. Applications would duplicate acknowledgement ordering, leases,
cancellation, retries, deadline handling, and cleanup.

### Provide a scheduler-neutral core runner with app-owned callbacks

Selected. It preserves normal Stem APIs and gives apps a small integration
boundary. A thin optional convenience adapter can be considered after the core
contract is implemented and validated; it must not register itself implicitly.

## Consequences

- Stem does not replace WorkManager or promise always-on execution.
- Users retain control of charging/network constraints, OS-visible progress,
  cancellation, and platform-specific eligibility.
- Scheduler retries rerun a queue-processing invocation; Stem retries remain
  task-level decisions. Re-running a callback must not recreate logical tasks.
- Cross-process configuration, producer-to-scheduler wakeup reconciliation, and
  cancellation propagation must be documented and tested.
- The application example invokes the tested bounded runner rather than
  presenting a timed `StemApp.start()` as safe. Native lifecycle acceptance is
  still required for the application's real workload and OS policy.

See the [mobile background execution guide](../../../stem_flutter/doc/background-execution.md)
for the integration boundary, platform limits, and implementation checklist.
