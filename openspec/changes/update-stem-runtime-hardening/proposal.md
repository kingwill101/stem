## Why
- Redis broker maintenance routines have gaps: queue purges ignore priority streams and periodic claim timers keep running after consumers shut down, leaving deliveries stranded and wasting Redis resources.
- The CLI `stem health` check only validates Redis result backends, so Postgres-backed deployments surface false negatives despite healthy connectivity.
- Worker heartbeat transports cannot connect to TLS-protected Redis instances, blocking secure environments from emitting liveness data.
- Without addressing these issues, operators face stuck jobs, noisy health checks, and blind spots in observability.

## What Changes
- Specify broker maintenance requirements covering priority stream purges and timer teardown when consumers disconnect.
- Extend CLI health requirements to detect both Redis and Postgres backends.
- Require heartbeat transports to honour shared TLS configuration.
- Implement the fixes, add regression tests, and exercise them against `docker/testing/docker-compose.yml` so we validate the integrated stack.

## Impact
- Prevents phantom deliveries after purge operations and stops idle brokers from hammering Redis with claim commands.
- Makes `stem health` trustworthy for all supported backends.
- Restores heartbeat publishing in secure Redis deployments.
- Adds a small amount of CI time for new integration coverage but significantly improves confidence.
