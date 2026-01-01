# Complete Stem Infrastructure Testing Guide

This guide provides a complete Docker-based testing infrastructure for the Stem project, including PostgreSQL, Redis, Prometheus, Grafana, and OpenTelemetry Collector.

## Quick Start

### 1. Start All Services

```bash
cd packages/stem_cli/docker/testing

# Start all services (postgres, redis, prometheus, grafana, otel-collector)
docker compose up -d

# Wait for health checks
docker compose up -d --wait --wait-timeout 60
```

### 2. Export Test Environment Variables

```bash
# Source the initialization script
source ../../_init_test_env

# Or manually export:
export STEM_TEST_REDIS_URL="redis://127.0.0.1:56379"
export STEM_TEST_POSTGRES_URL="postgresql://postgres:postgres@127.0.0.1:65432/stem_test"
export STEM_TEST_POSTGRES_TLS_URL="postgresql://postgres:postgres@127.0.0.1:65432/stem_test"
export STEM_TEST_POSTGRES_TLS_CA_CERT="$(pwd)/certs/postgres-root.crt"
```

### 3. Run Tests

From the repository root:

```bash
# Run all tests
dart test -r expanded -j 1

# Run specific package tests
dart test packages/stem_postgres -r expanded
dart test packages/stem_redis -r expanded
dart test packages/stem_cli -r expanded
```

## Service Architecture

### Core Services (Required for Testing)

#### PostgreSQL (Port: 65432)
- **Purpose**: Durable broker, result backend, and scheduler storage
- **TLS**: Enabled with self-signed certificates for testing
- **Database**: `stem_test`
- **User**: `postgres` / Password: `postgres`
- **Health Check**: Every 5s, max 10 retries with 10s startup grace period

#### Redis (Port: 56379)
- **Purpose**: In-memory broker, locks, rate limiting, and schedules
- **Databases**: 10 (configured for multiple queue namespaces)
- **Health Check**: Every 5s, max 10 retries with 10s startup grace period

### Observability Services (Optional, for Monitoring)

#### Prometheus (Port: 9090)
- **Purpose**: Metrics collection and aggregation
- **Access**: http://localhost:9090
- **Features**: 
  - Scrapes metrics from OTEL Collector
  - 24-hour retention
  - Local time-series database
- **Config**: `prometheus.yml`
- **Health Check**: Every 10s, max 5 retries with 10s startup grace period

#### Grafana (Port: 3000)
- **Purpose**: Dashboard and metrics visualization
- **Access**: http://localhost:3000
- **Default Credentials**: admin / admin
- **Features**:
  - Prometheus datasource pre-configured
  - Redis datasource support
  - PostgreSQL datasource support
  - Redis plugin for advanced metrics
- **Health Check**: Every 10s, max 5 retries with 10s startup grace period

#### OpenTelemetry Collector (Ports: 4317/gRPC, 4318/HTTP, 8888/Metrics, 13133/Health)
- **Purpose**: Tracing, metrics, and logs collection and export
- **Features**:
  - OTLP receivers (gRPC and HTTP)
  - Prometheus exporter for metrics
  - Batch processor for efficiency
  - Memory limiter for resource constraints
- **Config**: `collector-config.yaml`
- **Health Check**: Every 10s, max 5 retries with 10s startup grace period

## Common Tasks

### View Service Status

```bash
# Check all containers
docker compose ps

# View logs for specific service
docker compose logs postgres -f
docker compose logs redis -f
docker compose logs prometheus -f
docker compose logs grafana -f
docker compose logs otel-collector -f

# View all logs
docker compose logs -f
```

### Access Service UIs

- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3000
- **PostgreSQL Direct**: `psql postgresql://postgres:postgres@127.0.0.1:65432/stem_test`

### Database Operations

#### Connect to PostgreSQL

```bash
psql postgresql://postgres:postgres@127.0.0.1:65432/stem_test
```

#### Check Database Size

```bash
docker compose exec postgres psql -U postgres -d stem_test -c "
  SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
  FROM pg_tables
  WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
  ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;"
```

#### Check Active Connections

```bash
docker compose exec postgres psql -U postgres -c "
  SELECT 
    datname,
    count(*) as connections
  FROM pg_stat_activity
  GROUP BY datname;"
```

### Redis Operations

#### Connect to Redis

```bash
docker compose exec redis redis-cli -n 0
```

#### Monitor Redis Activity

```bash
docker compose exec redis redis-cli -n 0 monitor
```

#### Clear Redis Databases

```bash
docker compose exec redis redis-cli FLUSHALL
```

### Stopping Services

```bash
# Stop all services (keep volumes)
docker compose stop

# Stop and remove containers (keep volumes)
docker compose down

# Complete cleanup (remove volumes too)
docker compose down -v

# Remove all Stem testing images
docker compose down -v --rmi all
```

## TLS Testing

The PostgreSQL service is configured with TLS support using self-signed certificates:

```bash
# TLS certificate location
packages/stem_cli/docker/testing/certs/postgres-root.crt

# TLS environment variables (exported by _init_test_env)
export STEM_TEST_POSTGRES_TLS_URL="postgresql://postgres:postgres@127.0.0.1:65432/stem_test"
export STEM_TEST_POSTGRES_TLS_CA_CERT="packages/stem_cli/docker/testing/certs/postgres-root.crt"

# Run TLS integration tests
dart test packages/stem_postgres/test/integration -r expanded
```

## Testing Workflows

### Full Integration Test Suite

```bash
# Start services
cd packages/stem_cli/docker/testing
docker compose up -d --wait --wait-timeout 60

# Export environment
source ../../_init_test_env

# Run all tests
cd /path/to/repository/root
dart test -r expanded -j 1

# Check results
# Expected: All tests should pass
# 27+ tests in stem_postgres
# 30+ tests in stem_redis
# 42+ tests in stem_cli
```

### Verify Specific Adapters

```bash
# PostgreSQL adapter tests
dart test packages/stem_postgres -r expanded --verbose

# Redis adapter tests  
dart test packages/stem_redis -r expanded --verbose

# CLI integration tests
dart test packages/stem_cli -r expanded --verbose
```

### Health Check Test

```bash
# Run the CLI health check
dart run bin/stem.dart health

# Expected output:
# ✓ Redis connection: OK
# ✓ PostgreSQL connection: OK
# ✓ Broker: OK
# ✓ Result Backend: OK
```

## Troubleshooting

### Services Won't Start

```bash
# Check Docker daemon
docker ps

# View error logs
docker compose logs --tail 50

# Force cleanup and restart
docker compose down -v
docker compose up -d --wait --wait-timeout 60
```

### Health Check Failures

```bash
# Check service health
docker compose ps

# If unhealthy, inspect logs
docker compose logs <service-name>

# Force restart unhealthy service
docker compose restart <service-name>
```

### Database Connection Issues

```bash
# Test PostgreSQL connectivity
docker compose exec postgres pg_isready -U postgres

# Test Redis connectivity
docker compose exec redis redis-cli ping

# Check if ports are bound
netstat -tuln | grep -E '(65432|56379)'
```

### Migration or Schema Issues

```bash
# Reset PostgreSQL data (careful!)
docker compose down -v postgres
docker compose up -d postgres --wait --wait-timeout 60

# Migrations will auto-run on first connection
dart test packages/stem_postgres -r expanded
```

## Environment Variables Reference

| Variable | Value | Purpose |
|----------|-------|---------|
| `STEM_TEST_REDIS_URL` | `redis://127.0.0.1:56379` | Redis broker connection |
| `STEM_TEST_POSTGRES_URL` | `postgresql://postgres:postgres@127.0.0.1:65432/stem_test` | PostgreSQL connection |
| `STEM_TEST_POSTGRES_TLS_URL` | Same as above (TLS enabled) | PostgreSQL TLS connection |
| `STEM_TEST_POSTGRES_TLS_CA_CERT` | `./certs/postgres-root.crt` | PostgreSQL TLS CA certificate |
| `STEM_BROKER_URL` | Depends on broker choice | Broker connection string |
| `STEM_RESULT_BACKEND_URL` | Depends on backend choice | Result backend connection string |

## Performance Tuning

### PostgreSQL Configuration

The docker-compose includes optimizations for testing:

```yaml
# Shared buffer size (256MB for test)
POSTGRES_INITDB_ARGS: "-c shared_buffers=256MB -c max_connections=200"

# Command-line args
- "-c log_statement=all"      # Log all SQL for debugging
- "-c log_duration=on"        # Log execution duration
```

### Redis Configuration

```yaml
# Number of databases for test namespaces
--databases 10

# Disable persistence for faster tests
--appendonly no
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Integration Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - uses: dart-lang/setup-dart@v1
        with:
          sdk: stable
      
      - name: Start services
        run: |
          cd packages/stem_cli/docker/testing
          docker compose up -d --wait --wait-timeout 120
      
      - name: Run tests
        run: |
          source packages/stem_cli/_init_test_env
          dart test -r expanded
      
      - name: Stop services
        if: always()
        run: |
          cd packages/stem_cli/docker/testing
          docker compose down -v
```

## Next Steps

1. **Run the full test suite** to verify setup
2. **Explore Grafana dashboards** at http://localhost:3000
3. **Monitor metrics** via Prometheus at http://localhost:9090
4. **Review test logs** to understand integration points
5. **Extend observability** by implementing custom metrics in workers
