# Multi-worker routing demo

The default entrypoints use three normal Stem workers:

| Consumer identity | Explicit subscription |
| --- | --- |
| `general-a` | `mobile-demo` |
| `general-b` | `mobile-demo` |
| `routing-worker` | `mobile-routing` |

Each has one task-isolate slot, a distinct `consumerName`, its own core app and
owned connections, and the same SQLite file layout. Both general workers attach
their own registered workflow runtime. The routing worker executes ordinary
tasks without a workflow layer.

`demo_workers.dart` is app ownership/configuration code: it invokes the existing
factories, `start`, `runUntilIdle`, and shutdown methods. It does not implement
dispatch, claims, leases, retry policies, a consume loop, or a worker-message
protocol. Routing probes use `TaskEnqueueOptions(queue: ...)`; the UI reads
the executing worker from persisted `TaskStatus.meta['worker']`.

## Verification completed

- Full example suite: **108 tests passed**, serial execution, two-minute test
  timeout for real SQLite/CPU cases.
- Example analysis: no issues.
- Five real SQLite worker tests cover two independently gated consumers sharing
  a queue, unique delivery execution and persisted worker identities, a dedicated
  queue, report production in one app and execution in another, and independent
  bounded idle.
- Controller/UI tests cover queue selection, persisted identity, partial
  publication, wakeup failure, observer disposal, narrow layouts, and preventing
  Android UI bootstrap from starting its own headless consumers.
- Callback tests verify aggregate outcomes do not hide a permanent failure,
  processed counts are combined only after all workers drain, and an empty
  reconciliation does not keep scheduling itself.
- Profile APK built successfully and installed on the connected phone through
  wireless ADB. USB disconnected during the first install attempt; later ADB
  interaction became unresponsive before native probe distribution was verified.

## Native acceptance still needed

Open **Workers**, send six probes to `mobile-demo`, then another batch to
`mobile-routing`. Inspect the persisted queue/worker fields. Both general workers
may compete for the first batch; equal distribution is not guaranteed. Only the
routing worker should execute the second batch. Repeat while photos and workflow
runs are queued to demonstrate the same standard routing mechanisms together.

Foreground mode starts the configured workers normally. Android uses one native
callback hosting three bounded Stem workers concurrently, not three guaranteed
parallel native engines. After a productive callback it requests one extra
reconciliation pass for work published after another worker became idle; an
empty pass stops. This is host scheduling, not a substitute for core draining.

The earlier image-memory and workflow phone experiments used the previous
single-worker topology. Their measurements are not multi-worker memory ceilings
or validation of every stale-lease/process-kill scenario. Normal shared-queue
operation is supported; those recovery edge cases remain separate tests.
