## ADDED Requirements
### Requirement: Consumer Feature Guides Cover Core Stem Capabilities
Stem's public documentation MUST provide a feature-oriented guide for each primary capability (tasks/retries, producer API, worker runtime, scheduler, routing/broadcasts, signals, observability, persistence, CLI/control), written for Dart application developers and backed by runnable code snippets.

#### Scenario: Developer reads feature docs to embed Stem
- **GIVEN** a developer installs Stem from pub.dev
- **WHEN** they open the documentation site
- **THEN** they MUST find a dedicated section for each Stem capability listed above, each containing clearly written, concise examples (tabbed with labelled filenames when multiple variants/backends apply) and cross-links to related guides.

#### Scenario: Feature docs emphasise in-memory first, external services optional
- **GIVEN** a developer wants to run Stem locally without external dependencies
- **WHEN** they follow the feature guides
- **THEN** each guide MUST include an in-memory example before describing Redis/Postgres (or other) variants and clearly label external dependencies as optional.

#### Scenario: Feature docs cover breadth of feature surface
- **GIVEN** a feature guide (e.g., tasks, scheduler, routing, observability)
- **WHEN** a developer reads the page
- **THEN** the guide MUST summarise the major sub-features (options, APIs, signals, tooling) for that capability and illustrate each with brief, runnable snippets so developers understand how to apply them immediately.

#### Scenario: Navigation highlights developer-facing docs
- **GIVEN** the documentation sidebar and index pages
- **WHEN** a developer browses the site
- **THEN** the navigation MUST expose the feature guides above and MUST NOT include ops-only or contributor-only documents; such material MUST be moved to an internal contributor area.
