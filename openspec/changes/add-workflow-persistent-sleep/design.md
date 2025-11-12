# Design: Persistent workflow sleeps

## Overview
We already persist `requestedResumeAt` and `resumeAt` when a step suspends via
`FlowContext.sleep`. We will treat the suspension metadata as authoritative:
when the step replays after waking, the default `sleep` helper will detect that
metadata and avoid re-scheduling the delay if the wake timestamp is already in
the past.

## Runtime changes
- Flow/script executions already retain `_resumePayload`. We will store this
  metadata inside the execution context.
- `FlowContext.sleep` checks `_resumeData`: if the payload indicates a prior
  sleep (`type == 'sleep'`) and the stored `resumeAt` is `<= now`, the helper
  returns a no-op rather than emitting a suspend control. This lets simple loops
  call `sleep` unconditionally while still progressing after the delay.
- When the payload indicates `resumeAt` is still in the future (e.g. the run was
  rewound), the helper converts the remaining duration into a new suspend call.

## Store considerations
- Stores already persist suspension metadata (the runtime writes
  `resumeAt`/`requestedResumeAt`). No schema changes required.

## Testing
- Adapter contract suite gains a regression test verifying the stored
  suspension metadata includes `resumeAt` and survives round-trips.
- Runtime test exercises a step that loops with plain `ctx.sleep(duration);` and
  confirms the step advances after a single wake.
