## 1. SLO Definition
- [x] 1.1 Decide on initial SLOs (task success rate, task latency p95, queue depth) and document thresholds.
- [x] 1.2 Record owners/escalation paths in the operations guide.

## 2. Grafana Dashboards & Alerts
- [x] 2.1 Update dashboard JSON to include panels for the SLO metrics.
- [x] 2.2 Add Grafana alert definitions (provisioning files) for each SLO signal.
- [x] 2.3 Ensure docker-compose metrics example provisions updated dashboards/alerts.

## 3. Validation & Docs
- [x] 3.1 Update README/docs with alert setup/runbook references.
- [x] 3.2 `dart analyze`, `dart test`, `tool/quality/run_quality_checks.sh`, and `openspec validate add-observability-alerts --strict` (coverage now 63.21%).
