## ADDED Requirements
### Requirement: Expanded Schedule Types
Stem scheduler MUST support interval, cron, solar, and clocked schedule specifications with per-entry timezone handling.

#### Scenario: Solar schedule triggers at sunrise
- **GIVEN** a schedule entry set to sunrise for a specific latitude/longitude
- **WHEN** the scheduler evaluates due entries
- **THEN** it MUST compute the correct sunrise time for that day and enqueue the task once per day.

#### Scenario: Clocked schedule runs once
- **GIVEN** a clocked schedule for `2025-01-01T00:00:00Z` with `runOnce=true`
- **WHEN** that timestamp arrives
- **THEN** the scheduler MUST run the task exactly once and mark it completed, preventing future runs.

### Requirement: Runtime Schedule Management
Operators MUST be able to list, add, update, enable/disable, and delete periodic tasks at runtime via CLI/API without restarting the scheduler.

#### Scenario: CLI disable entry
- **GIVEN** an enabled schedule entry
- **WHEN** `stem schedule disable <id>` is executed
- **THEN** the entry MUST stop firing immediately and remain disabled across restarts until re-enabled via `stem schedule enable <id>`.

#### Scenario: Update schedule interval
- **GIVEN** a schedule entry running every hour
- **WHEN** the operator updates it to every 10 minutes via `stem schedule apply`
- **THEN** the next run MUST honor the new cadence without restarting the scheduler.

### Requirement: Drift & History Tracking
Scheduler MUST record last run, next run, total runs, and log drift corrections for observability.

#### Scenario: Drift detection
- **GIVEN** a schedule entry expected at 12:00:00
- **AND** the scheduler executes it at 12:00:15 due to clock skew
- **WHEN** drift exceeds the configured tolerance
- **THEN** the scheduler MUST log a drift warning and adjust next run to compensate.

#### Scenario: History inspection
- **GIVEN** completed runs
- **WHEN** `stem schedule list` is executed with a connected store
- **THEN** the CLI MUST display last run time, next run time, total runs, and last error (if any) for each schedule.
