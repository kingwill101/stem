# ADR 0001: Redis Streams as MVP Broker & Backend

## Status
Accepted (v1).

## Context
We need a single broker/backend combination that provides reliable delivery,
lease semantics, and delay queues while keeping the stack lightweight for Dart
devs.

## Decision
Use Redis Streams for the broker with Redis key/value structures for the result
backend and scheduler.

## Consequences
- Developers require Redis 7+ (Streams + XAUTOCLAIM).
- Allows a single dependency to power broker, backend, scheduler, and locks.
- Future adapters (RabbitMQ, SQS, Postgres) remain possible via existing
  interfaces.
