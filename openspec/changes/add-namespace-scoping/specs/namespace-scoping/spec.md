## ADDED Requirements

### Requirement: Namespace scoping across adapters
The system SHALL scope all broker, result backend, workflow, schedule, lock, revoke, and heartbeat data by namespace across Redis, Postgres, and SQLite adapters.

#### Scenario: Isolation between namespaces
- **WHEN** two adapters use different namespaces against the same backing store
- **THEN** data written in namespace A SHALL NOT be visible to namespace B

#### Scenario: Default namespace
- **WHEN** an adapter is constructed without an explicit namespace
- **THEN** it SHALL use the default namespace `stem`

### Requirement: SQL namespace persistence
The system SHALL persist namespace values for SQL-backed adapters and include namespace filters in all queries.

#### Scenario: Namespace stored on insert
- **WHEN** a SQL adapter writes a record
- **THEN** the stored row SHALL include the adapter namespace

#### Scenario: Namespace filter on read
- **WHEN** a SQL adapter reads or lists records
- **THEN** it SHALL filter results by the adapter namespace

### Requirement: Redis namespace prefixing
The system SHALL prefix Redis keys and channels with the adapter namespace.

#### Scenario: Redis key isolation
- **WHEN** two Redis adapters use different namespaces
- **THEN** they SHALL operate on distinct keyspaces
