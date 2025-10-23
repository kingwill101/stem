# ADR 0002: Ack After Result Write

## Status
Accepted (v1).

## Context
Workers must update the result backend and acknowledge the broker message.
Ordering affects duplicate handling and visibility timeouts.

## Decision
Write task results to the backend **before** acknowledging the broker message.
For Redis/Redis deployments we keep the operations separate for simplicity; a
future optimisation will use a Lua script to atomically `XACK` + `SET` when
needed.

## Consequences
- If a worker crashes between backend write and ack, the task may reappear and
  handlers must be idempotent.
- Keeping the operations separate avoids scripting requirements for non-Redis
  backends.
- Document the potential duplicate execution and provide guidance in the
  developer docs.
