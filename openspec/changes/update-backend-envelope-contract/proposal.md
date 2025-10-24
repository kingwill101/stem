## Why
- Envelope signing/verification currently lives in producers and workers, but our specs never state that result backends must persist envelopes without mutating signature headers. Codifying this avoids regressions when new backends are introduced.
- We want explicit requirements and regression tests proving that every backend round-trips signed envelopes untouched.

## What Changes
- Clarify Stem's core requirements so backends must treat envelope headers (including signatures) as opaque.
- Add a regression suite that stores and retrieves signed envelopes across each backend implementation.
- Update docs/tests accordingly without altering existing signing flow.

## Impact
- Guarantees future backends remain compatible with signing.
- Provides confidence that signatures survive through result persistence.
- No behavioural change for producers/workers; purely specification + test reinforcement.
