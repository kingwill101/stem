## ADDED Requirements

### Requirement: Chord callbacks dispatch independent of producer liveness
Chord callbacks MUST be enqueued exactly once when the group completes even if the process that initiated the chord is no longer running.

#### Scenario: Producer exits before chord completion
- **GIVEN** a chord with body tasks `[resize:1, resize:2]` and callback `notify.user`
- **AND** the initiating process terminates after publishing the body
- **WHEN** all body tasks eventually report `succeeded`
- **THEN** a worker-coordinated component MUST enqueue the callback exactly once with the collected results
- **AND** the callback task id MUST be observable via the result backend

### Requirement: Chord completion guard prevents duplicate callbacks
The system MUST guard chord completion so that, despite multiple coordinators observing group success, only one callback enqueue occurs.

#### Scenario: Competing coordinators observe completion
- **GIVEN** two workers detect that chord `chrd-42` has all body tasks completed
- **WHEN** both attempt to dispatch the callback
- **THEN** exactly one callback envelope MUST be published
- **AND** the losing coordinator MUST record that dispatch was already handled without creating a duplicate task
