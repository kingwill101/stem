# Proposal: Fake clock for workflow stores and runtime tests

## Problem
Our workflow contract tests rely on real time (sleeping/delays) to simulate wake-ups and timeouts. This makes tests slower and non-deterministic. Absurd solved this by allowing stores to inject a fake clock (e.g. `absurd.fake_now`). Stem should adopt a similar hook so stores and timer loops can be advanced programmatically in tests.

## Goals
- Provide a fake clock interface that workflow stores and runtime can consult instead of `DateTime.now()`.
- Update in-memory store (and optionally Postgres/SQLite via dependency injection) so contract tests can advance time instantly.
- Reduce reliance on real-time sleeps in unit/integration tests.

## Non-Goals
- Changing production behaviour; defaults should continue using real time.
- Replacing `Duration`-based APIs with tick-based scheduling.

## Measuring Success
- Workflow runtime tests no longer require `Future.delayed` to simulate timer polling.
- Fake clock helper is documented and used across adapter test suites.
