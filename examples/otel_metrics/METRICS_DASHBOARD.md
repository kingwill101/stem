# Viewing Metrics Dashboard

## 🚀 What Changed?

**The Problem**: Jaeger is designed for distributed **tracing**, not **metrics** visualization. That's why you weren't seeing your metrics in the Jaeger dashboard.

**The Solution**: We've added Prometheus (metrics storage) and Grafana (visualization) to your stack.

## 🎯 Quick Start

1. **Start all services:**
   ```bash
   cd examples/otel_metrics
   docker compose up --build
   ```

2. **Wait for all services to be ready** (~30 seconds)

3. **Access the dashboards:**
   - **Grafana (Metrics Dashboard)**: http://localhost:3000
     - Username: `admin`
     - Password: `admin`
     - **Pre-configured dashboard "STEM Worker Metrics" will be available!**
   - **Prometheus (Raw Metrics)**: http://localhost:9090
   - **Jaeger (Traces - for future use)**: http://localhost:16686

4. **View your metrics:**
   - In Grafana, click on **Dashboards** → **STEM Worker Metrics**
   - You should immediately see task execution rates, durations, and more!

## 📊 Viewing Metrics in Grafana

1. Open http://localhost:3000
2. Login with `admin` / `admin`
3. Go to **Explore** (compass icon in left sidebar)
4. Select **Prometheus** as the data source
5. Query your metrics:
   - Type `stem_` and you'll see autocomplete suggestions
   - Example queries:
     - `stem_task_duration_seconds_count` - Number of tasks executed
     - `stem_task_duration_seconds_sum` - Total task duration
     - `rate(stem_task_duration_seconds_count[1m])` - Tasks per minute
     - `rate(stem_task_duration_seconds_sum[1m]) / rate(stem_task_duration_seconds_count[1m])` - Average task duration

## 📈 Creating a Dashboard

1. In Grafana, click **+ (plus)** → **Dashboard**
2. Click **Add visualization**
3. Select **Prometheus** as data source
4. Add your metrics queries
5. Customize the visualization (graph, gauge, stat, etc.)
6. Click **Save** to save your dashboard

### Example Dashboard Panel Queries

**Task Execution Rate:**
```promql
rate(stem_task_duration_seconds_count{task="metrics.ping"}[1m])
```

**Average Task Duration:**
```promql
rate(stem_task_duration_seconds_sum[1m]) / rate(stem_task_duration_seconds_count[1m])
```

**Task Success/Failure Count:**
```promql
sum by (status) (stem_task_duration_seconds_count)
```

## 🔍 Viewing Metrics in Prometheus

1. Open http://localhost:9090
2. Go to **Graph** tab
3. Enter a metric name (e.g., `stem_task_duration_seconds_count`)
4. Click **Execute**
5. View as Table or Graph

## 🐛 Troubleshooting

### No metrics showing up?

1. **Check if collector is receiving metrics:**
   ```bash
   docker compose logs collector | grep "stem"
   ```

2. **Check Prometheus is scraping:**
   - Go to http://localhost:9090/targets
   - Ensure `otel-collector` target is UP

3. **Check worker is sending metrics:**
   ```bash
   docker compose logs worker
   ```

4. **Verify metrics endpoint:**
   ```bash
   curl http://localhost:8888/metrics | grep stem
   ```

### Collector shows errors?

- Ensure all services are running: `docker compose ps`
- Restart services: `docker compose restart`

## 📝 Available Metrics

Based on your worker configuration, you should see:

- `stem_task_duration_seconds` - Histogram of task execution times
  - Labels: `task`, `status`, `worker`, `queue`
  - Buckets: 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0 seconds

## 🎨 Understanding the Stack

### Why Not Jaeger for Metrics?

Jaeger is designed for **distributed tracing** (tracking requests across services), not for metrics visualization. 

### What Each Component Does:

- **Worker** → Generates metrics and sends them to OTLP endpoint
- **OTEL Collector** → Receives metrics via OTLP, exports to Prometheus
- **Prometheus** → Stores time-series metrics data
- **Grafana** → Visualizes metrics with beautiful dashboards
- **Jaeger** → For distributed tracing (when you add trace instrumentation later)

### The Data Flow:

```
Worker (Dart) 
  → Metrics via HTTP (OTLP/JSON)
  → OTEL Collector (port 4318)
  → Prometheus exporter (port 8888)
  → Prometheus scrapes every 15s
  → Grafana queries Prometheus
  → You see beautiful dashboards! 📊
```

## 🔧 Configuration Files Created

We've added these files to your setup:

1. **prometheus.yml** - Prometheus configuration (scrapes collector every 15s)
2. **grafana-datasources.yml** - Auto-configures Prometheus as Grafana data source
3. **grafana-dashboard.json** - Pre-built dashboard with 8 panels
4. **grafana-dashboards.yml** - Auto-provisions the dashboard on startup

## 📸 What You'll See

The pre-configured dashboard includes:

1. **Task Execution Rate** - Tasks processed per minute over time
2. **Average Task Duration** - How long tasks take to complete
3. **Total Tasks Executed** - Running total counter
4. **Tasks per Status** - Pie chart of success/failure
5. **Current Execution Rate** - Real-time task throughput
6. **Task Duration Percentiles** - p50, p90, p99 latencies
7. **Tasks by Queue** - Distribution across queues
8. **Tasks by Worker** - Distribution across workers

## 🔗 Learn More

- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [Prometheus Query Language](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [OpenTelemetry Metrics](https://opentelemetry.io/docs/concepts/signals/metrics/)
- [STEM OpenTelemetry Plugin](../../packages/otel/README.md)

## 💡 Next Steps

1. **Customize the dashboard** - Add your own panels and queries
2. **Set up alerts** - Get notified when metrics cross thresholds
3. **Add more metrics** - Instrument other parts of your application
4. **Add tracing** - Use the STEM OTEL tracing features with Jaeger