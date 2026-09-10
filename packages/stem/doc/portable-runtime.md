# Portable runtime integration

Import `package:stem/portable.dart` for producers, event-driven handlers,
and scheduled-event entrypoints. Use the existing `stem.dart` / `stable.dart`
barrels or `vm.dart` for VM workers. JavaScript compilation does not make
the VM worker lifecycle available in an event-driven runtime.

## Publishing and observing

Implement `TaskPublisher.publish` for a platform binding. There is no need
to provide fake consumer, acknowledgement, or close methods.
`TaskPublisherLifecycle` is optional for publishers owning connections.

`Stem.withPublisher` accepts a `taskStatusStore` and an optional
`groupResultStore`. Neither requires heartbeat storage. Explicit stores take
precedence over the corresponding capability of a compatibility `backend`.
The application owns explicitly supplied stores; `Stem.close()` only closes
the compatibility backend and publishers advertising a lifecycle.

## Processing and settling a batch

For each message:

1. Decode its envelope. Handle malformed transport bodies at the adapter boundary.
2. Read its status by `Envelope.id`, if a status store is configured.
3. Call `TaskProcessor.process`, supplying the status and execution controls.
4. Persist the outcome before acknowledging terminal work.
5. Settle **that message**, independently of all other messages in the batch.

Suggested mappings:

| Outcome | Adapter responsibility |
| --- | --- |
| `TaskProcessSuccess` | Encode/persist the result, then acknowledge |
| `TaskProcessRetry` | Retry with its delay, or publish `nextEnvelope` |
| `TaskProcessFailure` | Persist failure and apply the platform DLQ policy |
| `TaskProcessRejected` | Record the rejection and apply a poison-message policy |
| `TaskProcessCancelled` | Persist cancellation/expiry and acknowledge |
| `TaskProcessSkipped` | Acknowledge the already-terminal duplicate |

Infrastructure failures during persistence or settlement are not handler
failures. Do not acknowledge a message whose required durable write failed.
An adapter should isolate per-message failures rather than use a batch-wide
acknowledgement that loses failed work.

Native retries may retain the original body. Normalize a one-based native
attempt counter to zero-based `deliveryAttempt`; the processor preserves
the logical ID and verifies the original signed body before using the override.
When republishing a changed `nextEnvelope`, re-sign it before sending.
Native retry APIs cannot change the message body: adapters needing to preserve
explicit retry policy/time-limit overrides must republish the new envelope or
durably store those overrides rather than silently discard them.

For automatic retries with an explicit retry policy, a zero `defaultDelay`
means immediate retry even when `backoffMax` is set. Exponential scaling uses
an attempt exponent bounded to 0–30 and saturates at a duration whose
microseconds are exactly representable on JavaScript before applying
`backoffMax` and jitter.
This keeps large retry counters consistent across VM and JavaScript.

## Idempotency is not exactly-once execution

A terminal status suppresses a **sequential** duplicate. Two concurrent
deliveries can both observe no terminal status and execute. The regression
tests deliberately demonstrate this boundary.

Use the stable task ID as an application idempotency key. Atomic terminal
arbitration can choose one result writer, but does not prevent duplicate handler
side effects. Cross-instance execution suppression requires an adapter-specific
atomic claim with ownership/expiry semantics, or application-level idempotency.
This release does not provide a `TaskClaimStore` or claim exactly-once execution.

Backends can advertise `AtomicTerminalResultStore` directly. Both the VM worker
and payload-encoding wrapper recognize this capability, as well as its legacy
`AtomicTerminalResultBackend` subtype.

## One-shot scheduling

```dart
await ScheduleRunner(
  store: schedules,
  publisher: publisher,
  lockStore: locks,
).runOnce();
```

The runner does not start a daemon timer. If a lock store is supplied, temporary
renewal timers protect dispatch and are cancelled when dispatch finishes.
Lock TTLs must be positive; sub-millisecond TTLs are accepted, though actual
timer resolution depends on the host. Renewal failures mark the lease lost.
`Beat` retains its compatibility constructors and start/stop lifecycle while
using the same runner. Its periodic passes do not overlap, and failed passes
are logged without stopping future ticks. Separate callers of `runOnce()` must
still coordinate concurrent passes. Schedule publication and `markExecuted` are not atomic;
a crash between them can cause a later duplicate publication.

`portable.dart` exports `StemMetrics` and the metrics exporter API so portable
applications can configure and inspect scheduler and task metrics.

## VM worker integration

`Worker` and `TaskProcessor.process` use the same execution-middleware chain
and automatic/explicit retry classification. The worker supplies its existing
execution supervisor to `TaskProcessor.invoke`, preserving isolate termination
and inline timeout semantics. It still owns validation at its delivery boundary,
leases, persistence, acknowledgement, signing retry publications, linked tasks,
groups/chords, signals, and telemetry. The worker intentionally does not call
the portable `process` method, which would bypass its execution supervisor.

Portable inline timeouts stop waiting; they cannot forcibly stop arbitrary
asynchronous side effects. Handlers must observe cancellation at safe points.

## Validation

The portable CI workflow compiles the API to JavaScript and executes producer,
scheduler, processor, context, mixed-batch, and idempotency tests on Node.
The test-only Node bootstrap exposes Node's real WebCrypto implementation as a
data property because Node 24's global accessor rejects the receiver used by
`package:test`'s VM sandbox. No insecure RNG or fake crypto is substituted.

Provider-specific bindings and deployed Cloudflare integration remain the
responsibility of the integration package; the core tests use transport-neutral
fakes, not a deployed Cloudflare service.
