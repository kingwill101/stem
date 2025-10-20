## Documentation Plan

### Structure
- `/docs/developer-guide.md`: Intro, installation, configuration, enqueueing tasks, running workers/beat, handling retries, instrumentation.
- `/docs/operations-guide.md`: Deployment topologies, Redis/Postgres setup, secret management, upgrades, failure recovery.
- `/docs/scaling-playbook.md`: Capacity planning, isolate pool sizing formulas, horizontal scaling patterns (k8s, VM), rate limiting strategies.
- Example apps under `/examples`:
  - `examples/monolith_service`: Single Dart service with HTTP endpoint enqueueing tasks, worker/beat in same repo.
  - `examples/microservice`: Separate enqueue API and worker package communicating over Redis with docker-compose.

### Tooling
- Use mkdocs or Dart doc generation for consistent navigation (final choice TBD, default to mkdocs if time permits).
- Ensure example apps are covered by CI (smoke tests using `dart test` or integration script).

### Scaling Guidance Content
- Provide formulas for concurrency: `worker isolates = min(cpu*2, maxConcurrency)`.
- Document best practices for Redis (clustered vs single node, persistence, failover) and Postgres (connection pooling, TTL cleanup).
- Include checklists for launching additional worker nodes and verifying heartbeat/metrics.

## Open Questions
- Do we bundle docker-compose for microservice example? (Proposed: yes, to demonstrate multi-service bootstrapping.)
- Should docs adopt a site generator immediately? (Optional; start with markdown, leave TODO for doc site conversion.)
