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

The full documentation lives in the Docusaurus site under `.site/`.

```bash
cd .site
npm install
npm start
```

You'll find guides covering developer onboarding, operations, scaling, and
runbooks for the new `stem dlq` tooling.

### Examples

Two runnable example apps demonstrate common topologies:

- `examples/monolith_service` – single process service using in-memory adapters.
- `examples/microservice` – enqueue API and worker communicating through Redis.

Each example has a README with setup instructions.

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
