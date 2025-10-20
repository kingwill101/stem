# Stem Roadmap & Milestones

## Milestones

### M1 – Core Runtime
- Redis Streams broker & Redis result backend
- Worker daemon (prefetch, retries, lease renewal)
- CLI basics (`stem enqueue`, `stem observe metrics`)

### M2 – Scheduling & DLQ
- Beat (interval/cron + jitter + locks)
- Dead-letter queues with CLI list/show/replay
- Backoff tuning + rate limiter integration

### M3 – Observability & Docs
- OpenTelemetry metrics/traces/logging
- CLI/Docs for observability, scaling, quick start
- Samples (monolith, microservice, OTLP stack)

### M4 – Resilience Enhancements
- Hard timeouts & isolate pool polish
- Reclaim daemon & rate limiter store
- Locks/rate limiter robustness + release process docs

## Definition of Ready (DoR)
- User story linked to OpenSpec change/spec delta.
- Acceptance criteria include success/failure behaviour, error handling, docs/test notes.
- Dependencies (other stories, infrastructure) documented.

## Definition of Done (DoD)
- `dart format`, `dart analyze`, `dart test` pass locally & in CI.
- Relevant docs (developer, ops, quick start) updated.
- Examples compile/run if affected.
- Observability metrics/traces updated when behaviour changes.
- OpenSpec tasks updated to `- [x]` with evidence (links, tests).

## Tracking
- Use GitHub milestones M1–M4 mirroring the above.
- Label issues with `milestone:Mx` and `type:doc`, `type:impl`, `type:test` as appropriate.
- Review DoR/DoD compliance during grooming.

## Backlog / Outstanding Phase Work
- **Phase 5 (Testing)**: chaos/performance/soak suites, coverage targets, deterministic CI builds.
- **Phase 6 (Observability)**: implement dashboards/alerts (Grafana) tied to the SLOs and document owners.
- **Phase 7 (Security)**: payload signing helper, TLS automation scripts, recurring vulnerability scans.
- **Phase 9 (Release)**: Beta/RC pilot tracking, automated changelog generation.
- **Phase 10 (Ops)**: CLI pause/resume/drain, auto-scaling hints, roadmap refinement (RabbitMQ/SQS, Postgres backend).
