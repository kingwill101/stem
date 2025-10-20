## ADDED Requirements

### Requirement: Developer Integration Guide
Stem MUST provide a developer guide that walks through installing Stem, registering tasks, enqueueing, and running worker/beat components within a Dart application, including code samples that compile and run.

#### Scenario: Developer follows quickstart
- **GIVEN** a developer reads `/docs/developer-guide.md`
- **WHEN** they follow the quickstart steps
- **THEN** they MUST be able to run a provided example app that enqueues a task and observes the worker completing it using documented commands

### Requirement: Operations & Scaling Playbook
Stem MUST document recommended deployment patterns, isolate pool sizing strategies, and procedures for scaling workers/beat horizontally across hosts.

#### Scenario: Operator executes scaling checklist
- **GIVEN** an operator references `/docs/scaling-playbook.md`
- **WHEN** they need to add capacity for a spike in workload
- **THEN** the playbook MUST outline isolate sizing formulas, Redis/Postgres tuning recommendations, and a step-by-step checklist for adding workers while monitoring heartbeats and metrics

### Requirement: Runnable Examples
Stem MUST ship runnable example projects (monolith and microservice layouts) that demonstrate configuring Stem, enqueuing tasks, and running worker/beat processes.

#### Scenario: CI validates examples
- **GIVEN** the repository CI executes the example smoke tests
- **WHEN** the examples are run
- **THEN** they MUST pass lint/build checks and enqueue at least one task processed successfully, ensuring documentation examples remain up-to-date
