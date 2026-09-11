# Adapter lifecycle audit following bounded worker execution

## Outcome

The SQLite changes are **not** sufficient to establish the same guarantees for
all transports. Existing CI passes do not cover all outstanding-prefetch and
close-during-claim cases. This report records validation, not completed fixes.

| Adapter | Finding | Evidence |
| --- | --- | --- |
| Redis | Each `XREADGROUP` uses `COUNT prefetch`, then reads again without accounting for outstanding deliveries. `XAUTOCLAIM` has its own batch size. | Local injected-command probe delivered three messages without any ACK using `prefetch: 1`. The existing three broker unit tests passed. No live Redis service was available. |
| PostgreSQL | Consumer loop claims a batch each iteration without accounting for outstanding leases. Stop does not join its loop. | Source tracing; package analysis passed. Integration suite skipped because its database URL was unset. |
| Memory | Actual per-consumer outstanding-prefetch accounting exists, but broker close does not complete its consumer streams. | Local probe observed `onDone == false` after awaiting broker close; explicit subscription cancellation was still necessary. Existing 12 broker tests passed. |

Relevant implementations:

- [Redis consumption](../../stem_redis/lib/src/brokers/redis_broker.dart#L593)
  and [claim scheduling](../../stem_redis/lib/src/brokers/redis_broker.dart#L916).
- [PostgreSQL consumer loop](../../stem_postgres/lib/src/brokers/postgres_broker.dart#L1047).
- [Memory disposal](../lib/src/memory/brokers/in_memory_broker.dart#L90)
  and [consumption](../lib/src/memory/brokers/in_memory_broker.dart#L164).

## Additional lifecycle paths requiring regressions

- Redis dedicated blocking-read sockets must be stopped and joined; broker
  close currently does not retain all consumer connections. In shared-connection
  mode, blocking reads serialize ACK, lease extension, and other commands behind
  the read. Shared mode is the test factory default, not the normal connection
  factory default.
- Redis same-name subscriptions share PEL ownership and claim-timer keys.
  Cancelling one can affect another's timer. Define whether shared names are
  rejected, intentionally shared, or internally isolated.
- PostgreSQL close snapshots work while a consumer can still submit a subsequent
  operation. Connection recovery must not reopen a connection after close.
  Sweeper/cleanup jobs also need owned lifecycle and error handling.
- Redis result-backend close iterates a mutable watcher map while awaiting
  controller closure. PostgreSQL result/workflow connection disposal does not
  explicitly join its shared transaction queue. Add gated-write/cleanup/close
  tests before concluding these operations are safe.
- Memory same-name cancellation clears outstanding accounting while pending
  leases remain. Test redelivery and resubscription together rather than only
  successful ACK paths.

These additional findings are source-based risk paths, not live Redis or
PostgreSQL reproductions. Do not represent skipped integration tests as passes.

## Shared contract work

The shared adapter and memory result/workflow test selection passed 67 tests.
It covers ordinary results, watches, TTL, groups, due runs, and workflow leases,
but does not enforce the following broker lifecycle cases:

1. With prefetch one, no second queue delivery is admitted before capacity is
   freed by settlement or valid lease expiry. Include claim/reclaim paths.
2. Cancellation during a blocked read/claim leaves every message either emitted
   under a recoverable lease or safely available again.
3. Close prevents new internal work, joins owned poll/claim/maintenance operations,
   completes streams, and releases owned connections exactly once.
4. Repeated close and late completion cannot reopen connections or notify closed
   watchers.
5. Lease extension and recovery retain correct accounting across cancellation
   and same-name consumers according to each transport's declared semantics.

Already-emitted unacknowledged deliveries may deliberately retain their leases
until expiry; that is not itself message loss. Tests must assert recoverability,
not indiscriminately require immediate requeue. Likewise, closing a persistent
result backend must **not delete its stored results**. Post-close handle behavior
and reopening durable storage are distinct contract questions.

Memory workflow renewal after expiry and `dueRuns(limit: 0)` also warrant
focused contract tests, but are separate from the SQLite prefetch/drain fix.
Do not turn this audit into unverified cross-adapter implementation changes.
