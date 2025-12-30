## Example Audit (Existing Coverage vs. Required Scenarios)

This audit maps current examples under `packages/stem/example` to the required
scenarios in `specs/examples/spec.md` and highlights gaps.

### Covered

- **Delayed + rate-limited enqueue demo**
  - **Example**: `rate_limit_delay`
  - **Notes**: Demonstrates `notBefore`, rate limiter denial/deferral, and
    priority clamping with explicit log output and CLI inspection commands.

- **DLQ operations sandbox**
  - **Example**: `dlq_sandbox`
  - **Notes**: Shows failed tasks, DLQ list/show, and replay workflows via CLI.

- **Worker control lab**
  - **Example**: `worker_control_lab`
  - **Notes**: Demonstrates `stem worker ping|stats|inspect|revoke|shutdown`
    across two worker processes.

- **Progress + heartbeat reporting**
  - **Example**: `progress_heartbeat`
  - **Notes**: Logs `worker.events` progress/heartbeat events and documents
    `stem observe workers` for backend heartbeats.

### Partial Coverage (needs dedicated walkthrough)

- **Scheduler observability drill**
  - **Signals demo**: `signals_demo` logs `schedule_entry_*` signals and drift
    metrics.
  - **Microservice**: `microservice` runs Beat schedules and documents `stem schedule`
    commands, but not drift/failure observability.
  - **Gap**: No dedicated “drift + failure” runbook with explicit CLI checks
    or metrics dashboard links.

- **Signing key rotation exercise**
  - **Microservice**: README discusses rotating `STEM_SIGNING_ACTIVE_KEY`.
  - **Security examples**: `security/hmac`, `security/ed25519_tls` show signing.
  - **Gap**: No runnable drill that verifies overlap acceptance across active
    + old keys with explicit validation steps.

- **Progress + heartbeat reporting**
  - **Multiple examples** emit `context.progress(...)` and `context.heartbeat()`
    (e.g., `microservice`, `monolith_service`, `postgres_worker`, `redis_postgres_worker`).
  - **Gap**: No single “progress/heartbeat” demo with CLI inspection steps.

### Missing (no example yet)

- **Autoscaling walkthrough**
  - No example that demonstrates dynamic concurrency changes based on load.

- **Ops health suite**
  - No example that ties together `stem worker status --stream`, `stem observe tasks`,
    and health checks in a single runbook.

- **Quality gates runner**
  - No example scripts for format/analyze/test/coverage/chaos gates.
