## ADDED Requirements
### Requirement: Dashboard Supports SQLite Data Source
Operators MUST be able to launch the Stem dashboard against a SQLite database file produced by the embedded broker/backend.

#### Scenario: Connect Dashboard To Local Database
- **GIVEN** a developer on desktop runs `stem dashboard --sqlite path/to/stem.db`
- **WHEN** the dashboard server starts
- **THEN** it opens the SQLite database in read-only mode
- **AND** renders the overview page without runtime errors.

### Requirement: Dashboard Displays SQLite Queue Metrics
When backed by SQLite, the dashboard MUST surface queue depth, in-flight counts, and dead-letter totals so operators can evaluate contention.

#### Scenario: Overview Shows Queue Statistics
- **GIVEN** the SQLite queue contains pending, locked, and dead-letter rows
- **WHEN** the dashboard overview page loads
- **THEN** the page lists each queue with pending, inflight, and dead-letter counts derived from SQLite aggregates.

### Requirement: Dashboard Streams SQLite Heartbeat Updates
The dashboard MUST publish worker heartbeat updates via Turbo streams when the result backend stores heartbeats in SQLite.

#### Scenario: Worker Heartbeat Updates Stream
- **GIVEN** a worker sends periodic heartbeats into the SQLite result backend
- **WHEN** the dashboard workers page is open
- **THEN** the Turbo stream updates the worker table within two polling intervals after each heartbeat write.
