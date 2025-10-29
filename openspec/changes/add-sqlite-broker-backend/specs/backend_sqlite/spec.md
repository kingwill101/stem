## ADDED Requirements
### Requirement: SQLite Result Backend Stores Task States
Stem MUST expose a `SqliteResultBackend` so task outcomes persist locally with TTL semantics.

#### Scenario: Store And Retrieve Task Status
- **GIVEN** a task completes successfully through a worker connected to the SQLite backend
- **WHEN** the worker calls `storeResult` with state `succeeded` and a payload
- **AND** a client later calls `getTaskStatus` with the same task id before the TTL expires
- **THEN** the backend returns the stored payload and metadata.

### Requirement: SQLite Result Backend Manages Groups
Chord/group aggregation MUST operate when the result backend stores intermediate task outcomes in SQLite.

#### Scenario: Group Result Aggregation
- **GIVEN** a task chord registers a group expecting two members
- **WHEN** both member tasks report via `storeGroupResult`
- **THEN** the backend marks the group complete
- **AND** exposes the aggregated results via `getGroupResults`.

### Requirement: SQLite Result Backend Tracks Worker Heartbeats
The SQLite backend MUST accept worker heartbeats and surface them for observability consumers.

#### Scenario: Heartbeat Listing
- **GIVEN** a worker publishes a heartbeat with its isolate count and queue list
- **WHEN** the dashboard requests `listWorkerHeartbeats`
- **THEN** the backend returns the heartbeat payload
- **AND** excludes entries whose `expires_at` has passed.
