## Why
- Broker and result backend implementations each re-implement overlapping test suites, increasing the risk that adapters miss core behavioural guarantees.
- The new SQLite adapters highlighted gaps where contract expectations (dead-letter replay, lease handling, heartbeat persistence) must stay aligned with Redis/Postgres baselines.
- Packaging shared contract tests encourages contributors to exercise every adapter against the same scenarios before shipping.

## What Changes
- Introduce a reusable test package that exposes broker and result-backend compliance suites parameterised by adapter factories.
- Ensure the suites cover enqueue/consume/ack flows, dead-letter replay, lease expiry, and result persistence / group aggregation / heartbeat semantics.
- Document how adapters integrate the shared tests and update existing adapter packages to consume them.

## Impact
- Standardises behavioural coverage for future adapters (e.g., SQLite, Redis, Postgres, SQS) while reducing duplicated test code.
- Lowers the chance of regressions or missing features when introducing new broker or backend implementations.
- Adds minimal build overhead as suites run once per adapter, but replaces multiple bespoke tests.
