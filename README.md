## Stem

Stem is a spec-driven background job platform for Dart. It provides task
registration, Redis Streams integration, isolate-aware workers, retries, a beat
scheduler, and CLI tooling for observability and dead-letter remediation.

### Highlights

- At-least-once delivery semantics with configurable retry strategies.
- Isolate pool execution with soft and hard time limits.
- Redis Streams broker (plus in-memory adapters for tests).
- Result backend with group/chord primitives.
- CLI support for schedules, observability snapshots, and DLQ replay.
- OpenTelemetry metrics and heartbeat events.

### Documentation

The documentation site lives in `.site/`.

```bash
cd .site
npm install
npm start
```

Quick links:

- [Quick Start](.site/docs/quick-start.md)
- [Developer Guide](.site/docs/developer-guide.md)
- [Operations Guide](.site/docs/operations-guide.md)
- [Broker Comparison](.site/docs/broker-comparison.md)
- [Release Process](.site/docs/release-process.md)

### Examples

Three runnable example apps demonstrate common topologies:

- `examples/monolith_service` – single process service using in-memory adapters.
- `examples/microservice` – enqueue API and worker communicating through Redis.
- `examples/otel_metrics` – worker + OpenTelemetry collector + Jaeger via Docker Compose.

Each example has a README with setup instructions and links back to the docs.

### CLI Quick Reference

```bash
stem schedule list
stem observe metrics
stem dlq list --queue default --limit 20
stem dlq replay --queue default --limit 10 --yes
```

See `openspec/changes/` for the spec deltas that drive the implementation. Pull
requests should include updated specs and passing `openspec validate --strict`,
`dart format`, and `dart test` runs.
