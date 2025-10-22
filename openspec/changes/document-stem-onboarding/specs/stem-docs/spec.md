## MODIFIED Requirements

### Requirement: Developer Integration Guide
Stem MUST provide a developer guide that walks through installing Stem, registering tasks, enqueueing, and running worker/beat components within a Dart application, including code samples that compile and run.

#### Scenario: Onboarding journey leads to deployment readiness
- **GIVEN** a newcomer starts at `.site/docs/getting-started/`
- **WHEN** they follow the documented sequence (prerequisites, local quick start, connecting to Redis/Postgres, observability, deployment checklist)
- **THEN** they MUST finish with a runnable task, understand how to configure production infrastructure, and have a checklist covering deployment verification steps and operational follow-ups
- **AND** each page MUST link to the next logical step so readers never lose the path

#### Scenario: Feature coverage with runnable examples
- **GIVEN** Stem’s core feature set (pipeline, worker operations & signals, observability, security/deployment, enablement & quality)
- **WHEN** the newcomer reaches the end of the getting-started journey
- **THEN** the documentation MUST have introduced each feature area with at least one runnable or copy-pasteable example snippet demonstrating usage (e.g., delayed enqueue, DLQ replay, worker autoscaling, telemetry export, payload signing)
- **AND** cross-links MUST point to the detailed reference pages for deeper dives into each capability
