# Design: Fault-Tolerant Chord Callbacks

## Current Implementation
- `Canvas.chord` publishes the body group and launches `_monitorChord`, a loop
  running in the caller’s isolate that polls `ResultBackend.getGroup` every
  100 ms.
- Once the group is complete, the loop immediately publishes the callback task
  and resolves the future.
- If the caller terminates before completion, no loop remains to enqueue the
  callback; the group results sit in the backend indefinitely.

## Requirements
- Callback dispatch must be independent of the initiating process.
- Dispatch must occur exactly once—even if multiple workers observe completion.
- The API must continue to return a future that eventually yields the callback
  task id or error.
- Implementation should reuse existing primitives where possible (e.g. result
  backend, broker).

## Proposed Architecture
1. **Chord Registry / Coordinator**: Introduce a component (likely part of
   worker startup) that subscribes to group updates via `ResultBackend.watchGroup`
   (if available) or efficient polling. For each chord, it tracks expected
   result count and uses an atomic compare/set flag in the backend to ensure a
   single callback publish.
2. **Backend Support**: Extend `ResultBackend` with operations such as
   `markChordDispatched(chordId)` returning `true` only for the first caller.
   Redis/Postgres implementations can use Lua / conditional updates to enforce
   atomicity.
3. **Canvas Changes**: Instead of spinning a local loop, `Canvas.chord`
   registers the chord with the coordinator (e.g. via a control channel or
   backend flag) and returns a future that resolves when the coordinator
   publishes the callback. For backward compatibility, Canvas can still monitor
   progress but rely on the coordinator’s dispatch signal to complete.
4. **Worker Integration**: Workers listen for “chord ready” events (e.g. backend
   pub/sub or lease) and execute the callback enqueue. Because workers are long
   lived, the callback will survive producer restarts.

## Alternative Considerations
- **Dedicated Chord Service**: Spinning a separate process simplifies worker
  responsibilities but adds operational overhead; deferred for future.
- **Callback inline with final task**: Having the final body task enqueue the
  callback could work but requires handlers to coordinate and still needs an
  atomic guard to stop multiple final tasks from firing the callback.
- **Broker Delay**: Using broker features (e.g. streams) to store chord state
  adds coupling and complicates portability.

## Observability
- Emit new signals: `chord.completed`, `chord.callback.enqueued`.
- Record metrics for time-to-callback and failure counts.
- Include chord id/task name as tags for tracing.

## Open Questions
- Should the coordinator live inside every worker or in a single leader? Initial
  approach: every worker participates but atomic backend guard ensures only one
  dispatch.
- How to handle chord failure (one body task fails)? Default behaviour should
  mark the chord as failed and avoid enqueuing the callback; expose result
  via backend for clients to observe.
