# Stem + OpenTelemetry Metrics Example

This example shows how to wire a Stem worker to an OpenTelemetry (OTLP/HTTP)
collector without spinning up Redis or other infrastructure. It uses the
in-memory broker/backend so you can focus on the telemetry pipeline.

## Prerequisites

1. Dart SDK 3.3+ (for local runs)
2. Docker with Compose v2
3. The provided OpenTelemetry collector + Jaeger UI (bundled configuration)

The collector forwards metrics to both a logging exporter and a Jaeger
all-in-one instance so you can inspect telemetry visually:

```yaml
receivers:
  otlp:
    protocols:
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch: {}

exporters:
  logging:
    loglevel: debug

service:
  pipelines:
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [logging]
```

### Run with Docker Compose

```bash
docker compose up --build
```

This brings up three containers:

- `collector`: OpenTelemetry collector listening on port `4318`
- `jaeger`: Jaeger all-in-one UI available at <http://localhost:16686>
- `worker`: Stem worker streaming metrics to the collector every second

Stop the stack with:

```bash
docker compose down
```

### Run locally

```bash
cd examples/otel_metrics
dart pub get
dart run bin/worker.dart
```

The worker enqueues a task every second, executes it, and emits metrics
(`stem.tasks.started`, `stem.tasks.succeeded`, `stem.task.duration`, etc.).
The collector logs the measurements and forwards them to Jaeger, where they
appear under the `metrics.ping` service.

## Notes

- `ObservabilityConfig` controls the namespace, heartbeat cadence, and metric
  exporter list. The example points to the OTLP HTTP endpoint.
- Heartbeats are disabled (`heartbeatInterval: Duration.zero`) because the
  example uses in-memory components. Swap in `RedisHeartbeatTransport` and a
  persistent backend when integrating with a real deployment.
- The custom OTLP exporter in Stem sends one JSON payload per data point. For
  production quality exporters consider swapping in a fully featured OTLP
  client or bridging to your preferred metrics backend.
