---
id: quick-start
title: Quick Start
sidebar_label: Quick Start
---

This walkthrough spins up Stem end-to-end in minutes.

## 1. Clone & Bootstrap

```bash
git clone <your-fork-url>
cd stem
``` 

## 2. Run the Docker Compose Stack

The OTLP metrics example ships with a collector and worker wired together.

```bash
cd examples/otel_metrics
docker compose up --build
```

This launches:

- **collector** – OpenTelemetry Collector forwarding metrics to Jaeger & logs
- **jaeger-ui** – Jaeger all-in-one UI at [http://localhost:16686](http://localhost:16686)
- **worker** – Stem worker enqueueing demo tasks every second

Watch the collector logs for `stem.*` metrics and inspect traces in Jaeger.

## 3. Explore the CLI Locally

Open a new terminal and install dependencies:

```bash
dart pub get
```

Run the in-memory examples (no Docker required):

```bash
cd examples/monolith_service
dart run bin/service.dart
```

In another terminal:

```bash
curl -X POST http://localhost:8080/enqueue -d '{"name":"Ada"}'
```

Observe worker logs and query task status via the service API.

## 4. Next Steps

- Read the [Developer Guide](developer-guide.md) for details on registering
  tasks, starting workers, and enabling observability.
- Review the [Operations Guide](operations-guide.md) and
  [Broker Comparison](broker-comparison.md) before deploying.
- Check out the [Scaling Playbook](scaling-playbook.md) when sizing clusters.
