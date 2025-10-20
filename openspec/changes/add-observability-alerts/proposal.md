## Why
- Phase 6 of the roadmap calls for concrete dashboards/alerts tied to SLOs with documented owners.
- Existing Grafana dashboards surface metrics, but alerts and owner docs are missing.

## What Changes
- Define SLO metrics (latency, success rate, queue depth) and create Grafana dashboards/alerts sourced from Prometheus.
- Document alert runbooks/ownership (operations guide & README).
- Automate dashboard provisioning in the metrics example/docker assets if needed.

## Impact
- Requires maintaining Grafana provisioning files and alert rules.
- Team needs to agree on SLO thresholds and responsible on-call engineers.
