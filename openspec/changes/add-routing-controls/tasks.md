## 1. Research & Design
- [ ] 1.1 Document current routing limitations across Redis/Postgres brokers and worker entrypoints.
- [ ] 1.2 Finalize routing data model (queues, exchanges, bindings, priorities, broadcast channels) and roll it into design.md.

## 2. Configuration & Registry
- [ ] 2.1 Introduce routing configuration schema (YAML/Dart) with default queue aliasing and queue definitions.
- [ ] 2.2 Implement routing registry/loader and unit tests covering resolution precedence.

## 3. Broker Enhancements
- [ ] 3.1 Extend `Broker.publish`/`consume` contracts for routing metadata (exchange, routing_key, priority, broadcast).
- [ ] 3.2 Update Redis broker for priority queues & broadcast fan-out, with integration tests.
- [ ] 3.3 Update Postgres broker (schema migrations + query changes) for routing metadata and priority ordering.

## 4. Worker & Runtime Updates
- [ ] 4.1 Enable workers to subscribe to multiple queues and broadcast channels based on routing config.
- [ ] 4.2 Ensure Stem enqueue path honours routing policies and logs routing decisions.

## 5. Tooling & Documentation
- [ ] 5.1 Update CLI/observability to surface routing metadata (queue bindings, priorities, broadcasts).
- [ ] 5.2 Document routing configuration with Celery migration guidance.

## 6. Validation
- [ ] 6.1 `dart format`, `dart analyze`, `dart test`, and new integration suites covering routing scenarios.
- [ ] 6.2 `openspec validate add-routing-controls --strict` before review.
