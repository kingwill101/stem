## 1. Research & Design
- [x] 1.1 Document current routing limitations across Redis/Postgres brokers and worker entrypoints.
- [x] 1.2 Finalize routing data model (queues, exchanges, bindings, priorities, broadcast channels) and roll it into design.md.

## 2. Configuration & Registry
- [x] 2.1 Introduce routing configuration schema (YAML/Dart) with default queue aliasing and queue definitions.
- [x] 2.2 Implement routing registry/loader and unit tests covering resolution precedence.

## 3. Broker Enhancements
- [x] 3.1 Extend `Broker.publish`/`consume` contracts for routing metadata (exchange, routing_key, priority, broadcast).
- [x] 3.2 Update Redis broker for priority queues & broadcast fan-out, with integration tests.
- [x] 3.3 Update Postgres broker (schema migrations + query changes) for routing metadata and priority ordering.

## 4. Worker & Runtime Updates
- [x] 4.1 Enable workers to subscribe to multiple queues and broadcast channels based on routing config.
- [x] 4.2 Ensure Stem enqueue path honours routing policies and logs routing decisions.

## 5. Tooling & Documentation
- [x] 5.1 Update CLI/observability to surface routing metadata (queue bindings, priorities, broadcasts).
- [x] 5.2 Document routing configuration with Celery migration guidance.

## 6. Validation
- [x] 6.1 `dart format`, `dart analyze`, `dart test`, and new integration suites covering routing scenarios.
- [x] 6.2 `openspec validate add-routing-controls --strict` before review.
