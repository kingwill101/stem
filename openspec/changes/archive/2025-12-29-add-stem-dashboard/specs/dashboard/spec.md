## ADDED Requirements

### Requirement: Stem Dashboard Observability
Stem MUST provide a Hotwire-powered dashboard that surfaces live Stem runtime data (overview metrics, task queues, events, workers) and exposes basic operator controls via a clean, navigable UI.

#### Scenario: Overview metrics and navigation
- **GIVEN** the dashboard is running
- **WHEN** an operator opens the Overview page
- **THEN** the sidebar MUST display `Overview`, `Tasks`, `Events`, and `Workers` sections and the page MUST show aggregated metrics (e.g., queued, processing, succeeded, failed) refreshed on an interval.

#### Scenario: Tasks table with drill-down
- **GIVEN** the Tasks page is open
- **WHEN** queued or historical tasks are listed
- **THEN** the table MUST support sorting/filtering, and clicking a row MUST expand detailed metadata (payload, timing, attempts, headers).

#### Scenario: Triggering jobs from dashboard
- **GIVEN** the Tasks page provides enqueue controls
- **WHEN** an operator submits a task via the UI
- **THEN** the dashboard MUST enqueue the task through Stem’s APIs, show success/failure feedback, and refresh the list to include the new task.

#### Scenario: Events stream
- **GIVEN** the Events page is open
- **WHEN** new task lifecycle events occur (enqueue, start, succeed, fail, retry)
- **THEN** the page MUST display them in chronological order with expandable rows and MUST update without a full page reload (polling or streaming).

#### Scenario: Worker visibility and control
- **GIVEN** the Workers page is open
- **WHEN** workers publish heartbeat/state data
- **THEN** the page MUST list all workers with status, queue focus, processed counts, uptime, and clicking a worker row MUST show details plus actions (ping, pause/resume, shutdown, replay DLQ) that execute via Stem.

#### Scenario: Routed Hotwire integration
- **GIVEN** the dashboard project depends on Routed Hotwire packages
- **WHEN** the project is built locally
- **THEN** dependency overrides MUST point to `~/code/dart_packages/routed_ecosystem/packages/routed_hotwire` (and required peers) so the app compiles without fetching remote packages.
