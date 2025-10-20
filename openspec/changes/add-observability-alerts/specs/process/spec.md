## MODIFIED Requirements

### Requirement: Milestones & SLO Runbooks
Stem MUST publish milestone definitions and operational runbooks for observability and security.
#### Scenario: SLO thresholds and ownership recorded
- **GIVEN** the on-call engineer reviews `docs/process/observability-runbook.md`
- **WHEN** they reference the SLO table
- **THEN** it MUST list thresholds, measurement windows, and alert identifiers for task success rate, task latency p95, and default queue depth
- **AND** ownership and PagerDuty escalation details MUST be documented for those alerts
- **AND** the operations guide (`.site/docs/operations-guide.md`) MUST link the SLO alerts so operators can find the runbook quickly
