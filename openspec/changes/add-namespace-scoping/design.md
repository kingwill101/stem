## Context
Namespaces exist today but are applied inconsistently across adapters. Redis prefixes keys; Postgres/SQLite stores accept a namespace parameter but ignore it for schedules/locks (and more). This makes cross-environment isolation unreliable.

## Goals / Non-Goals
- Goals:
  - Consistent namespace scoping across Redis, Postgres, and SQLite adapters.
  - Namespace must be persisted for SQL adapters and used in all queries.
  - Default namespace is `stem` when unspecified.
- Non-Goals:
  - Schema-per-namespace support.
  - Backward compatibility with previously prefixed workflow names.

## Decisions
- **SQL adapters use a namespace column** on all persisted tables (broker, backend, workflow, schedule, lock, revoke, heartbeat). All reads/writes filter by namespace.
- **Redis adapters continue prefixing keys** with the namespace, which is the equivalent isolation boundary.
- **Default namespace** remains `stem` and is applied when a caller omits it.
- **Workflow names/topics are no longer prefixed** in SQL adapters; the namespace column is the sole scoping boundary.

## Risks / Trade-offs
- **Breaking behavior**: previously unscoped reads now filter by namespace. Mitigate by defaulting to `stem` and migrating existing rows with default values.
- **Schema churn**: multiple tables gain a namespace column and new indexes.
- **Operational migration**: existing installations must run migrations.

## Migration Plan
1. Add namespace columns with default `stem` to Postgres/SQLite tables.
2. Backfill existing rows via default/NOT NULL constraint.
3. Update models and queries to include namespace filters.
4. Update tests to validate namespace isolation.

## Open Questions
- None.
