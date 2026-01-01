# Stem + OpenTelemetry Metrics Example

This example wires a Stem worker to an OpenTelemetry collector using the
in-memory broker/backend so you can focus purely on telemetry. The stack now
includes Prometheus for metrics storage and Grafana for dashboards in addition
to the collector and Jaeger.

## Prerequisites

1. Dart SDK 3.3+ (for local runs)
2. Docker with Compose v2
3. The provided OpenTelemetry collector + Jaeger UI (bundled configuration)

The collector forwards metrics to Prometheus and Jaeger:

```yaml
receivers:
  otlp:
    protocols:
      http:
        endpoint: 0.0.0.0:4318
      grpc:
        endpoint: 0.0.0.0:4317

processors:
  batch: {}

exporters:
  logging:
    verbosity: detailed
  prometheus:
    endpoint: 0.0.0.0:8888
    namespace: stem

service:
  pipelines:
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [logging, prometheus]
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlp/jaeger]
```

### Run with Docker Compose

```bash
docker compose down      # stop any previous run
docker compose up --build
```

This brings up:

- `collector` – OpenTelemetry collector (OTLP on 4317/4318, Prometheus scrape on 8888)
- `prometheus` – Prometheus UI at <http://localhost:9090>
- `grafana` – Grafana UI at <http://localhost:3000> (admin/admin)
- `jaeger` – Jaeger UI at <http://localhost:16686>
- `worker` – Stem worker streaming metrics every second

Stop the stack with `docker compose down`.

### Run locally

```bash
cd examples/otel_metrics
dart pub get
dart run bin/worker.dart
```

The worker enqueues a task every second, executes it, and emits metrics such as
`stem_tasks_started_total`, `stem_tasks_succeeded_total`, and
`stem_task_duration_seconds_bucket`. The collector exposes these on the
Prometheus scrape endpoint and forwards spans to Jaeger.

## Notes

- `ObservabilityConfig` controls the namespace, heartbeat cadence, and exporter
  list. The worker now uses the Dartastic OTLP gRPC exporter automatically.
- Heartbeats remain disabled (`heartbeatInterval: Duration.zero`) because the
  example uses in-memory components.
- After pulling changes, rebuild the stack (`docker compose down && docker compose up --build`)
  so Prometheus/Grafana pick up the latest dashboards and metric names.
- Grafana alerting is provisioned from `grafana-alerts.yml`. Update notification
  policies inside Grafana to target your PagerDuty or Slack channels so SLO
  alerts reach the right on-call engineers.

### Local build + Docker deps (just)

```bash
just deps-up
just build
just run
# Or:
just tmux
```
