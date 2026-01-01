## MODIFIED Requirements

### Requirement: Observability & Control
Stem MUST expose metrics through OpenTelemetry and provide tooling to inspect worker status.
#### Scenario: Grafana provisions SLO dashboards and alerts
- **GIVEN** the `examples/otel_metrics` stack is started via Docker Compose
- **WHEN** Grafana finishes provisioning bundled assets
- **THEN** the dashboard MUST include panels for task success rate, queue depth, and task latency p95 sourced from Prometheus
- **AND** matching alert rules MUST be installed with thresholds for each SLO and a runbook reference to `docs/process/observability-runbook.md`
- **AND** operators MUST be able to wire notification policies through Grafana contact points without modifying repository files
