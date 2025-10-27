# Design Notes

## Registry Changes
- Update `TaskRegistry.register` to accept an `overrideExisting` flag with a
  default of `false`. `SimpleTaskRegistry` will throw an `ArgumentError` if a
  handler with the same name is already registered and the caller did not
  request an override. Tests that intentionally swap handlers can opt-in.
- Add `Iterable<TaskHandler> get handlers;` to `TaskRegistry` so consumers can
  enumerate registered handlers. `SimpleTaskRegistry` exposes a read-only view
  backed by its internal map.
- Introduce `TaskMetadata` with optional description, tags, and idempotency flag
  to attach human-readable information to handlers. The default implementation
  returns an empty metadata object so existing handlers remain source-compatible.

## Typed Enqueue Helpers
- Introduce `TaskDefinition<TArgs, TResult>` to encapsulate the task name,
  default options, metadata, and a converter that maps typed arguments to the
  `Map<String, Object?>` form required by the broker.
- Add `TaskCall<TArgs, TResult>` instances emitted by a definition. Each call
  captures args, headers, overrides (options/meta/notBefore), and reuses the
  definition’s converters.
- Extend `Stem` with `enqueueCall(TaskCall call)` which encodes arguments and
  delegates to the existing `enqueue` implementation. This keeps tracing,
  routing, and middleware behavior unchanged while offering a type-safe facade.
- Supply convenience methods (`TaskDefinition.withoutArgs`) for fire-and-forget
  tasks that only need headers/options.

## Testing Strategy
- Unit test duplicate detection, override behavior, enumeration, and metadata on
  `SimpleTaskRegistry`.
- Add tests for `TaskDefinition` and `TaskCall` to ensure argument/meta encoding
  works and integrates with `Stem.enqueueCall`.
- Exercise failure cases (unregistered task, duplicate registration) to ensure
  errors are surfaced with clear messages.
