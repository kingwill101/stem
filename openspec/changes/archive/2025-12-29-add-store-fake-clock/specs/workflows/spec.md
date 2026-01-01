## ADDED Requirements

### Requirement: Workflow clock abstraction
The workflow runtime and stores MUST support plugging in a clock abstraction so tests can control time deterministically.

#### Scenario: Fake clock advances timers without real delay
- **GIVEN** a workflow runtime is constructed with a fake clock
- **AND** a run suspends until `clock.now + Duration(seconds: 60)`
- **WHEN** the test advances the fake clock by 60 seconds
- **THEN** the run MUST become due immediately without waiting for real wall-clock time.

#### Scenario: Stores honour injected timestamps
- **GIVEN** an adapter store receives timestamps provided by the runtime
- **WHEN** the runtime uses a fake clock
- **THEN** the store MUST rely on the provided timestamps (not `DateTime.now`) when persisting suspensions and due checks.
