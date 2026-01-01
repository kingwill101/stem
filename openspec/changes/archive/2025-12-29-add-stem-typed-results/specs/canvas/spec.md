## ADDED Requirements

### Requirement: Typed canvas primitives propagate results
Canvas helpers (task signatures, chains, groups, chords) MUST accept optional type parameters and decoder hooks so that sequential steps and callbacks receive strongly typed payloads. Chains MUST surface each step's typed output to the next step as both metadata (`chainPrevResult`) and strongly typed input, while chords MUST deliver a typed list of body results to the callback. Group helpers MUST preserve the declared type when returning aggregated statuses.

#### Scenario: Chain forwards typed outputs
- **GIVEN** a `Canvas.chain<Invoice>` composed of tasks that each declare `TaskSignature<Invoice>`
- **WHEN** step `A` completes successfully with a decoded `Invoice`
- **THEN** step `B` MUST receive that typed `Invoice` as its previous result (no casting required) and the chain helper MUST expose an API to decode each step result exactly once

#### Scenario: Chord callback receives typed list
- **GIVEN** a chord body declared with result type `Thumbnail`
- **AND** the callback expects `List<Thumbnail>`
- **WHEN** every body task succeeds
- **THEN** the chord helper MUST decode each payload (or cast primitives) according to the declared type, aggregate them into a typed list, and pass that list to the callback before enqueueing it

#### Scenario: Group status streaming preserves typing
- **GIVEN** a consumer calls `canvas.group<OrderSummary>(...)` to launch a fan-out
- **WHEN** the helper streams completions from the result backend
- **THEN** each emitted status MUST include the typed `OrderSummary` value alongside the raw `TaskStatus` so callers can update UX without manual casting
