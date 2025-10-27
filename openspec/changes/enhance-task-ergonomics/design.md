# Design Notes

## Fluent Task Enqueue Builder
- Introduce `TaskEnqueueBuilder<TArgs, TResult>` that wraps a `TaskDefinition`
  and allows callers to set headers, metadata, options, delay, and priority via
  chainable methods.
- The builder produces a `TaskCall` or directly invokes `Stem.enqueueCall`.

## Metadata Awareness in CLI
- Add a new CLI command `stem tasks ls` that loads the registry, iterates over
  `TaskRegistry.handlers`, and prints name, description, tags, and idempotency.
- Provide `--json` output for automation.

## Registry Watchers
- Extend `TaskRegistry` with a broadcast stream `onRegister` emitting
  `(String name, TaskHandler handler)` events when a handler is added or
  overridden. `SimpleTaskRegistry` will manage a `StreamController`.

## Testing Helpers
- Add `FakeStem` that implements `Stem`’s enqueue contract and records
  `TaskCall`s/arguments, enabling unit tests to assert enqueued jobs without a
  broker.
- Provide matchers/utilities (e.g. `expect(fake.enqueues, containsTask('foo'))`).

## Tracing Metadata
- Update `Stem.enqueue` to include `task.metadata` attributes (`tags`,
  `idempotent`, `description`) on the producer span.
