## ADDED Requirements

### Requirement: Backend-Agnostic Health Checks
The `stem health` command MUST validate connectivity to every configured result backend (Redis or Postgres) and report backend-specific diagnostics so operators can trust the status output.

#### Scenario: Postgres backend checked
- **GIVEN** `STEM_RESULT_BACKEND_URL` points to a Postgres instance
- **WHEN** `stem health` runs without `--skip-backend`
- **THEN** the command MUST attempt a Postgres connection, surface success when the database responds, and emit actionable error context if it fails

#### Scenario: Redis backend checked with TLS override
- **GIVEN** `STEM_RESULT_BACKEND_URL` is a Redis URI and `--allow-insecure` is omitted
- **WHEN** `stem health` executes
- **THEN** the command MUST honour the TLS config derived from environment variables and report handshake failures with hints to enable insecure mode only for debugging
