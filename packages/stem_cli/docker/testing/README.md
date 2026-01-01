# Stem Docker Testing Infrastructure

Complete Docker Compose setup for testing Stem with PostgreSQL, Redis, Prometheus, and Grafana.

## Quick Start (30 seconds)

```bash
# Start all services
docker compose up -d --wait --wait-timeout 60

# From repository root, export test environment
cd ../../..
source packages/stem_cli/_init_test_env

# Run tests
dart test -r expanded -j 1
```

## Services

### Required for Testing
- **PostgreSQL 14** (65432): Durable broker, backend, scheduler storage with TLS
- **Redis 7** (56379): In-memory broker, locks, rate limiting

### Optional for Monitoring
- **Prometheus** (9090): Metrics collection
- **Grafana** (3000): Dashboard visualization (admin/admin)
- **OpenTelemetry Collector**: Tracing and instrumentation

## Configuration Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Main service definitions |
| `prometheus.yml` | Metrics scraping config |
| `collector-config.yaml` | OTEL collector pipeline |
| `grafana-datasources.yml` | Pre-configured datasources |
| `TESTING.md` | Comprehensive testing guide |

## Environment Variables

Automatically exported by `_init_test_env`:
```bash
STEM_TEST_REDIS_URL
STEM_TEST_POSTGRES_URL
STEM_TEST_POSTGRES_TLS_URL
STEM_TEST_POSTGRES_TLS_CA_CERT
```

## Commands

```bash
# Start services
docker compose up -d --wait --wait-timeout 60

# Check status
docker compose ps

# View logs
docker compose logs -f [service-name]

# Test connectivity
docker compose exec postgres pg_isready -U postgres
docker compose exec redis redis-cli ping

# Stop services
docker compose stop

# Complete cleanup
docker compose down -v
```

## Dashboards

- Prometheus: http://localhost:9090
- Grafana: http://localhost:3000

## Documentation

- [TESTING.md](./TESTING.md) - Comprehensive guide with examples
- [../../../DOCKER-SETUP.md](../../../DOCKER-SETUP.md) - Quick reference
- [../../../INFRASTRUCTURE-CHECKLIST.md](../../../INFRASTRUCTURE-CHECKLIST.md) - Verification & troubleshooting

## Troubleshooting

**Services won't start**: Check Docker daemon, view logs with `docker compose logs --tail 50`

**Tests fail with connection error**: Ensure all services are healthy with `docker compose ps`

**PostgreSQL schema issues**: Reset with `docker compose down -v postgres && docker compose up -d postgres --wait`

**Ormed.yaml not found**: Run tests from package directories (e.g., `cd packages/stem_postgres && dart test`)

## Notes

- ✓ TLS enabled on PostgreSQL (self-signed for testing)
- ✓ Health checks with 10-second grace periods
- ✓ Persistent volumes for data
- ✓ Isolated `stem-testing` bridge network
- ✓ Performance tuned (256MB shared buffers, 200 max connections)

See [TESTING.md](./TESTING.md) for complete documentation.
